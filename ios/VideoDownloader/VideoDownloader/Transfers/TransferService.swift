import Foundation
import Observation
import os
import SwiftData
import UIKit
import YTVDAPI

/// Загрузки: Mac качает ролик, iPhone фоновой сессией забирает готовый файл.
///
/// Фоновая загрузка ставится сразу после создания задания и ждёт на сервере (wait=1),
/// пока Mac не докачает. Поэтому экран можно заблокировать сразу после «Скачать»:
/// передачей занимается система, а приложение она разбудит, когда файл придёт.
@Observable @MainActor
final class TransferService {

    static let shared = TransferService()

    private(set) var transfers: [Transfer] = []

    /// Обработчик от системы, пока она держит приложение проснувшимся ради фоновой сессии.
    @ObservationIgnored var backgroundCompletion: (() -> Void)?
    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private let delegate = SessionDelegate()
    @ObservationIgnored private let connection: Connection
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollGeneration = 0
    @ObservationIgnored private var lastSample: [UUID: (date: Date, bytes: Int64)] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "studio.dk.videodownloader", category: "transfers")

    /// Сколько раз подряд переподключаться после обрыва, прежде чем показать ошибку.
    static let maxAttempts = 6
    static let sessionIdentifier = (Bundle.main.bundleIdentifier ?? "videodownloader") + ".transfers"
    private static var storeURL: URL { LibraryFiles.root.appendingPathComponent("transfers.json") }

    init(connection: Connection? = nil) {
        self.connection = connection ?? .shared
        LibraryFiles.prepare()
        transfers = Self.load()

        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        // Сервер держит запрос файла, пока Mac качает (до 25 минут), — всё это время байтов нет.
        config.timeoutIntervalForRequest = 30 * 60
        config.timeoutIntervalForResource = 24 * 3600
        config.httpMaximumConnectionsPerHost = 2
        delegate.service = self
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    var active: [Transfer] { transfers.filter(\.isActive) }

    func transfer(_ id: UUID) -> Transfer? { transfers.first { $0.id == id } }

    /// Этот ролик в этом качестве уже качается — второй раз не ставим.
    func isDownloading(videoId: String, formatId: String) -> Bool {
        transfers.contains { $0.isActive && $0.video.id == videoId && $0.format.id == formatId }
    }

    // MARK: - начать

    func start(video: VideoInfo, format: VideoFormat, replacing: UUID? = nil) async throws {
        let client = try connection.client()
        try LibraryFiles.checkSpace(for: format.estimatedSize)
        let job = try await client.startDownload(url: video.sourceUrl, formatId: format.id)

        var snapshot = video
        snapshot.formats = []
        var transfer = Transfer(id: UUID(), jobId: job.jobId, server: client.baseURL,
                                video: snapshot, format: format)
        transfer.job = job
        transfer.replaces = replacing
        transfers.insert(transfer, at: 0)
        save()
        log.info("загрузка \(transfer.id.uuidString, privacy: .public): задание \(job.jobId, privacy: .public), \(format.label, privacy: .public)")

        enqueueFile(for: transfer)
        startPolling()
        Task { await cacheThumbnail(for: transfer.id) }
    }

    /// Фоновая загрузка файла. С resumeData — докачка с того места, где оборвалось.
    private func enqueueFile(for transfer: Transfer, resumeData: Data? = nil, delay: TimeInterval = 0) {
        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: connection.client(for: transfer.server).fileRequest(jobId: transfer.jobId))
        }
        task.taskDescription = transfer.id.uuidString
        if delay > 0 { task.earliestBeginDate = Date().addingTimeInterval(delay) }
        if let size = transfer.format.estimatedSize { task.countOfBytesClientExpectsToReceive = size }
        task.resume()
    }

    // MARK: - управление

    func cancel(_ id: UUID) async {
        guard let transfer = transfer(id) else { return }
        cancelTasks(for: id)
        remove(id)
        let client = connection.client(for: transfer.server)
        try? await client.cancel(transfer.jobId)
        try? await client.delete(transfer.jobId)
    }

    /// Повтор после ошибки: живое задание на Mac — забираем файл (с докачкой), нет — ставим заново.
    func retry(_ id: UUID) async {
        guard let transfer = transfer(id) else { return }
        update(id) {
            $0.phase = .mac
            $0.error = nil
            $0.attempts = 0
            $0.speed = nil
        }
        let client = connection.client(for: transfer.server)
        do {
            if let job = try? await client.job(transfer.jobId), !Self.isDead(job.status) {
                update(id) { $0.job = job }
                enqueueFile(for: transfer, resumeData: takeResumeData(for: id))
            } else {
                let job = try await client.startDownload(url: transfer.video.sourceUrl, formatId: transfer.format.id)
                deleteResumeData(for: id)
                update(id) {
                    $0.jobId = job.jobId
                    $0.job = job
                    $0.received = 0
                    $0.expected = nil
                }
                if let renewed = self.transfer(id) { enqueueFile(for: renewed) }
            }
            save()
            startPolling()
        } catch {
            fail(id, AppError.from(error).localizedDescription)
        }
    }

    /// Убрать строку из списка (после ошибки или отмены).
    func remove(_ id: UUID) {
        transfers.removeAll { $0.id == id }
        lastSample[id] = nil
        deleteResumeData(for: id)
        try? FileManager.default.removeItem(
            at: LibraryFiles.thumbnails.appendingPathComponent(LibraryFiles.thumbnailFileName(id: id)))
        save()
    }

    // MARK: - после перезапуска

    /// Загрузки, у которых нет живой фоновой задачи (приложение выгрузили, телефон перезагрузили),
    /// сверяем с Mac: никаких «вечных 63 %».
    func restore() async {
        let running = Set(await session.allTasks.compactMap(\.transferID))
        for transfer in transfers where transfer.isActive && !running.contains(transfer.id) {
            await reconnect(transfer.id)
        }
        startPolling()
    }

    private func reconnect(_ id: UUID) async {
        guard let transfer = transfer(id) else { return }
        do {
            let job = try await connection.client(for: transfer.server).job(transfer.jobId)
            if Self.isDead(job.status) {
                fail(id, job.error?.message ?? job.status.title)
                return
            }
            update(id) { $0.job = job }
            log.info("загрузка \(id.uuidString, privacy: .public) продолжена после перезапуска")
            enqueueFile(for: transfer, resumeData: takeResumeData(for: id))
        } catch let error as AppError where error.serverCode == APIErrorCode.jobNotFound.rawValue {
            fail(id, "Задание на Mac не найдено — скачайте заново")
        } catch {
            fail(id, "Нет связи с Mac: \(AppError.from(error).localizedDescription)")
        }
    }

    // MARK: - опрос Mac

    /// Пока приложение на экране, раз в секунду спрашиваем Mac, как идут дела.
    func startPolling() {
        guard pollTask == nil, transfers.contains(where: { $0.phase == .mac }) else { return }
        pollGeneration += 1
        let generation = pollGeneration
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.transfers.contains(where: { $0.phase == .mac }) else { break }
                await self.pollJobs()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if self?.pollGeneration == generation { self?.pollTask = nil }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollJobs() async {
        for transfer in transfers where transfer.phase == .mac {
            do {
                let job = try await connection.client(for: transfer.server).job(transfer.jobId)
                apply(job, to: transfer.id)
            } catch let error as AppError {
                if error.serverCode == APIErrorCode.jobNotFound.rawValue {
                    cancelTasks(for: transfer.id)
                    fail(transfer.id, "Задание на Mac пропало — скачайте заново")
                } else if error == .unauthorized {
                    cancelTasks(for: transfer.id)
                    fail(transfer.id, error.localizedDescription)
                }
                // Mac ненадолго пропал из сети — фоновая загрузка всё равно ждёт, просто не обновляем.
            } catch {}
        }
    }

    private func apply(_ job: JobInfo, to id: UUID) {
        guard let transfer = transfer(id), transfer.phase == .mac else { return }
        update(id) { $0.job = job }
        if Self.isDead(job.status) {
            cancelTasks(for: id)
            fail(id, job.error?.message ?? job.status.title)
        }
    }

    // MARK: - события фоновой сессии

    func didReceiveBytes(_ id: UUID, total: Int64, expected: Int64?) {
        guard let index = transfers.firstIndex(where: { $0.id == id }), transfers[index].isActive else { return }
        let now = Date()
        var transfer = transfers[index]
        let started = transfer.phase != .transfer
        if let last = lastSample[id] {
            let elapsed = now.timeIntervalSince(last.date)
            // Интерфейсу хватит четырёх обновлений в секунду.
            if elapsed < 0.25, !started, total < (expected ?? .max) { return }
            if elapsed > 0, total >= last.bytes {
                let instant = Double(total - last.bytes) / elapsed
                transfer.speed = transfer.speed.map { $0 * 0.7 + instant * 0.3 } ?? instant
            }
        }
        lastSample[id] = (now, total)
        transfer.phase = .transfer
        transfer.received = total
        transfer.expected = expected ?? transfer.job?.fileSize
        transfers[index] = transfer
        if started { save() }
    }

    func didFinish(_ id: UUID, file: URL) {
        guard let transfer = transfer(id) else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        let item = importItem(transfer, file: file)
        transfers.removeAll { $0.id == id }
        lastSample[id] = nil
        deleteResumeData(for: id)
        save()
        log.info("загрузка \(id.uuidString, privacy: .public) в библиотеке: \(item.fileSize) байт")
        Task { await afterImport(item, transfer: transfer) }
    }

    /// Сервер ответил не файлом, а ошибкой.
    func didGetResponse(_ id: UUID, status: Int, error: APIErrorBody?) {
        guard let transfer = transfer(id), transfer.isActive else { return }
        if status == 409, error?.code == APIErrorCode.notReady.rawValue {
            // Mac работает дольше, чем сервер держит запрос, — ставим ожидание заново.
            update(id) { $0.phase = .mac }
            enqueueFile(for: transfer, delay: 2)
            startPolling()
            return
        }
        let message = status == 401 ? AppError.unauthorized.localizedDescription
            : (error?.message ?? "Mac ответил ошибкой \(status)")
        fail(id, message)
    }

    func didFail(_ id: UUID, error: Error, resumeData: Data?) {
        // Неактивные — это те, что мы сами отменили или уже пометили ошибкой.
        guard let transfer = transfer(id), transfer.isActive else { return }
        let attempts = transfer.attempts + 1
        update(id) { $0.attempts = attempts; $0.speed = nil }
        let code = (error as NSError).code
        if attempts <= Self.maxAttempts {
            // Обрыв связи или выгрузка приложения: продолжаем с того же места, а не с нуля.
            log.info("загрузка \(id.uuidString, privacy: .public): обрыв \(code), попытка \(attempts)")
            enqueueFile(for: transfer, resumeData: resumeData, delay: Double(attempts) * 3)
            save()
        } else {
            if let resumeData { storeResumeData(resumeData, for: id) }
            fail(id, "Загрузка прервалась: \(AppError.from(error).localizedDescription)")
        }
    }

    /// Система будила приложение ради фоновой сессии — всё обработано, отпускаем её.
    func finishBackgroundEvents() {
        Task {
            await Task.yield()
            backgroundCompletion?()
            backgroundCompletion = nil
        }
    }

    // MARK: - в библиотеку

    private func importItem(_ transfer: Transfer, file: URL) -> VideoItem {
        let fm = FileManager.default
        let context = Persistence.container.mainContext
        let itemId = UUID()
        let ext = file.pathExtension.isEmpty ? (transfer.format.hasVideo ? "mp4" : "m4a") : file.pathExtension
        let fileName = "\(itemId.uuidString).\(ext)"
        let destination = LibraryFiles.videos.appendingPathComponent(fileName)
        try? fm.removeItem(at: destination)
        try? fm.moveItem(at: file, to: destination)

        var thumbnailName: String?
        if let cached = transfer.thumbnailName {
            let name = LibraryFiles.thumbnailFileName(id: itemId)
            if (try? fm.moveItem(at: LibraryFiles.thumbnails.appendingPathComponent(cached),
                                 to: LibraryFiles.thumbnails.appendingPathComponent(name))) != nil {
                thumbnailName = name
            }
        }
        let size = (try? fm.attributesOfItem(atPath: destination.path))?[.size] as? Int64

        let item = VideoItem(
            id: itemId, videoId: transfer.video.id, title: transfer.video.title,
            channel: transfer.video.channel, duration: transfer.video.duration ?? transfer.job?.duration,
            width: transfer.format.width, height: transfer.format.height, fps: transfer.format.fps,
            formatLabel: transfer.format.label, codec: transfer.format.codec,
            isAudioOnly: !transfer.format.hasVideo, fileName: fileName, thumbnailName: thumbnailName,
            fileSize: size ?? transfer.received, sourceURL: transfer.video.sourceUrl,
            platform: transfer.video.platform)
        context.insert(item)
        if let old = transfer.replaces, let previous = Library.item(old, in: context) {
            Library.delete(previous, in: context)
        }
        try? context.save()
        return item
    }

    /// Долгие мелочи после импорта: размер кадра, обложка, «Фото», уборка на Mac.
    private func afterImport(_ item: VideoItem, transfer: Transfer) async {
        let background = UIApplication.shared.beginBackgroundTask(withName: "Импорт видео")
        defer { UIApplication.shared.endBackgroundTask(background) }
        let context = Persistence.container.mainContext

        if !item.isAudioOnly, let size = await Library.videoSize(of: item.fileURL) {
            item.width = size.width
            item.height = size.height
        }
        if item.thumbnailName == nil {
            let name = LibraryFiles.thumbnailFileName(id: item.id)
            let early = LibraryFiles.thumbnails.appendingPathComponent(LibraryFiles.thumbnailFileName(id: transfer.id))
            if (try? FileManager.default.moveItem(at: early, to: LibraryFiles.thumbnails.appendingPathComponent(name))) != nil {
                item.thumbnailName = name
            } else if let data = await Self.downloadThumbnail(transfer.video.thumbnail),
                      LibraryFiles.storeThumbnail(data, name: name) {
                item.thumbnailName = name
            }
        }
        try? context.save()

        if UserDefaults.standard.bool(forKey: Prefs.autoSaveToPhotos), !item.isAudioOnly {
            do {
                try await PhotosSaver.save(item.fileURL)
            } catch {
                log.error("не сохранилось в «Фото»: \(AppError.from(error).localizedDescription, privacy: .public)")
            }
        }
        if !UserDefaults.standard.bool(forKey: Prefs.keepOnMac) {
            try? await connection.client(for: transfer.server).delete(transfer.jobId)
        }
    }

    private func cacheThumbnail(for id: UUID) async {
        guard let data = await Self.downloadThumbnail(transfer(id)?.video.thumbnail) else { return }
        let name = LibraryFiles.thumbnailFileName(id: id)
        guard LibraryFiles.storeThumbnail(data, name: name), transfer(id) != nil else { return }
        update(id) { $0.thumbnailName = name }
        save()
    }

    private static func downloadThumbnail(_ raw: String?) async -> Data? {
        guard let raw, let url = URL(string: raw),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    // MARK: - вспомогательное

    private static func isDead(_ status: JobStatus) -> Bool {
        status == .failed || status == .cancelled || status == .interrupted
    }

    private func update(_ id: UUID, _ change: (inout Transfer) -> Void) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        change(&transfers[index])
    }

    private func fail(_ id: UUID, _ message: String) {
        update(id) {
            $0.phase = .failed
            $0.error = message
            $0.speed = nil
        }
        save()
        log.error("загрузка \(id.uuidString, privacy: .public): \(message, privacy: .public)")
    }

    private func cancelTasks(for id: UUID) {
        session.getAllTasks { tasks in
            for task in tasks where task.transferID == id { task.cancel() }
        }
    }

    private func save() {
        do {
            try API.encoder.encode(transfers).write(to: Self.storeURL, options: .atomic)
        } catch {
            log.error("не сохранился список загрузок: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load() -> [Transfer] {
        guard let data = try? Data(contentsOf: storeURL),
              let list = try? API.decoder.decode([Transfer].self, from: data) else { return [] }
        return list
    }

    private func resumeURL(for id: UUID) -> URL {
        LibraryFiles.incoming.appendingPathComponent("\(id.uuidString).resume")
    }

    private func storeResumeData(_ data: Data, for id: UUID) {
        try? data.write(to: resumeURL(for: id), options: .atomic)
    }

    private func takeResumeData(for id: UUID) -> Data? {
        let url = resumeURL(for: id)
        defer { try? FileManager.default.removeItem(at: url) }
        return try? Data(contentsOf: url)
    }

    private func deleteResumeData(for id: UUID) {
        try? FileManager.default.removeItem(at: resumeURL(for: id))
    }
}

// MARK: - делегат фоновой сессии

/// Работает на очереди сессии. Готовый файл забирает сразу — после выхода из метода
/// система его удалит, — а всё остальное передаёт в главный поток.
final class SessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    weak var service: TransferService?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        // Байты ошибки (JSON с кодом 409) — не передача файла.
        guard let id = downloadTask.transferID, Self.isFileResponse(downloadTask.response) else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let service = self.service
        Task { @MainActor in service?.didReceiveBytes(id, total: totalBytesWritten, expected: expected) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.transferID else { return }
        let service = self.service
        let response = downloadTask.response as? HTTPURLResponse
        let status = response?.statusCode ?? 0

        guard Self.isFileResponse(response) else {
            let body = (try? Data(contentsOf: location))
                .flatMap { try? API.decoder.decode(APIErrorEnvelope.self, from: $0) }?.error
            Task { @MainActor in service?.didGetResponse(id, status: status, error: body) }
            return
        }

        let name = LibraryFiles.videoFileName(id: id, serverFileName: response?.suggestedFilename,
                                              isAudioOnly: response?.mimeType?.hasPrefix("audio") == true)
        let destination = LibraryFiles.incoming.appendingPathComponent(name)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in service?.didFinish(id, file: destination) }
        } catch {
            Task { @MainActor in service?.didFail(id, error: error, resumeData: nil) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.transferID else { return }
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let service = self.service
        Task { @MainActor in service?.didFail(id, error: error, resumeData: resumeData) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let service = self.service
        Task { @MainActor in service?.finishBackgroundEvents() }
    }

    private static func isFileResponse(_ response: URLResponse?) -> Bool {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { return false }
        return status == 200 || status == 206
    }
}

extension URLSessionTask {
    /// Какой загрузке принадлежит задача: храним её идентификатор в описании задачи.
    var transferID: UUID? { taskDescription.flatMap(UUID.init(uuidString:)) }
}
