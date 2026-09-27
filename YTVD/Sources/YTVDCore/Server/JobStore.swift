import Foundation
import os

/// Очередь заданий на скачивание для iPhone.
///
/// Задания выполняются внутри процесса — без Redis, Celery и прочего: это личный сервер.
/// Состояние хранится в JSON рядом с готовыми файлами, так что после перезапуска
/// готовое остаётся готовым, а прерванное честно помечается прерванным.
public actor JobStore {

    public struct Configuration: Sendable {
        public var directory: URL
        public var maxConcurrent: Int
        /// Сколько хранить готовые файлы на Mac, если iPhone их не забрал.
        public var retention: TimeInterval
        /// Сколько доверять разбору ссылки: ссылки YouTube живут 6 часов.
        public var resolveTTL: TimeInterval

        public init(directory: URL, maxConcurrent: Int = 1,
                    retention: TimeInterval = 48 * 3600, resolveTTL: TimeInterval = 600) {
            self.directory = directory
            self.maxConcurrent = max(1, maxConcurrent)
            self.retention = retention
            self.resolveTTL = resolveTTL
        }

        public static var standard: Configuration {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            return Configuration(directory: base.appendingPathComponent("YTVD/server", isDirectory: true))
        }
    }

    private struct Record: Codable {
        var info: JobInfo
        /// Имя файла в каталоге files — по идентификатору задания, не по названию ролика.
        var storedFile: String?
    }

    private struct CachedResolve {
        var video: VideoInfo
        var choices: [FormatChoice]
        var resolvedURL: URL
        var date: Date
    }

    private let config: Configuration
    private let makeEngine: @Sendable () -> any MediaEngine
    private let freeSpace: @Sendable (URL) -> Int64?
    private let thumbnailProbe: @Sendable (String) async -> Bool
    private let log = Logger(subsystem: "studio.dk.ytvd", category: "jobs")

    private var records: [String: Record] = [:]
    private var queue: [String] = []
    private var running: [String: Task<Void, Never>] = [:]
    private var engines: [String: any MediaEngine] = [:]
    private var cache: [String: CachedResolve] = [:]
    private var lastProgressAt: [String: Date] = [:]

    public init(config: Configuration = .standard,
                makeEngine: @escaping @Sendable () -> any MediaEngine,
                freeSpace: @escaping @Sendable (URL) -> Int64? = JobStore.availableSpace,
                thumbnailProbe: @escaping @Sendable (String) async -> Bool = JobStore.probeThumbnail) {
        self.config = config
        self.makeEngine = makeEngine
        self.freeSpace = freeSpace
        self.thumbnailProbe = thumbnailProbe

        let fm = FileManager.default
        try? fm.createDirectory(at: config.directory.appendingPathComponent("files"),
                                withIntermediateDirectories: true)
        // Недокачанное с прошлого раза — мусор: процесс, который его писал, уже умер.
        try? fm.removeItem(at: config.directory.appendingPathComponent("work"))
        records = Self.restore(from: config, retention: config.retention)
    }

    private var filesDirectory: URL { config.directory.appendingPathComponent("files") }
    private var indexURL: URL { config.directory.appendingPathComponent("index.json") }

    // MARK: - разбор ссылки

    public func resolve(url raw: String) async throws -> VideoInfo {
        try await resolveCached(url: raw).video
    }

    private func resolveCached(url raw: String, forceFresh: Bool = false) async throws -> CachedResolve {
        guard let url = LinkDetector.firstSupportedURL(in: raw) else {
            throw APIErrorBody(.invalidUrl, "Нужна ссылка на YouTube, Vimeo, Rutube или VK Видео")
        }
        let key = url.absoluteString
        if !forceFresh, let hit = cache[key], Date().timeIntervalSince(hit.date) < config.resolveTTL {
            return hit
        }

        let engine = makeEngine()
        let resolved: MediaService.Resolved
        do {
            resolved = try await engine.resolve(url: url)
        } catch {
            throw Self.apiError(from: error)
        }

        let info = resolved.info
        let choices = IPhoneFormats.build(from: info, canMerge: engine.capabilities.canMerge,
                                          canTranscode: engine.capabilities.canTranscode)
        guard choices.contains(where: \.format.hasVideo) || choices.contains(where: \.format.hasAudio) else {
            throw APIErrorBody(.formatUnavailable, "У ролика нет вариантов, которые iPhone сможет проиграть")
        }

        let video = VideoInfo(
            id: info.id ?? key, title: info.displayTitle, channel: info.displayAuthor,
            duration: info.duration, thumbnail: await workingThumbnail(info.thumbnailCandidates),
            sourceUrl: url.absoluteString, platform: MediaSource.detect(url).rawValue,
            formats: choices.map(\.format),
            recommendedFormatId: IPhoneFormats.recommended(choices))

        let entry = CachedResolve(video: video, choices: choices, resolvedURL: resolved.url, date: Date())
        cache[key] = entry
        return entry
    }

    /// Первая обложка, которая реально открывается: у старых роликов лучшей может не быть.
    private func workingThumbnail(_ candidates: [String]) async -> String? {
        for candidate in candidates.prefix(4) where await thumbnailProbe(candidate) {
            return candidate
        }
        return candidates.first
    }

    // MARK: - задания

    public func startDownload(url raw: String, formatId: String) async throws -> JobInfo {
        let resolved = try await resolveCached(url: raw)
        guard let choice = resolved.choices.first(where: { $0.format.id == formatId }) else {
            throw APIErrorBody(.formatUnavailable)
        }

        let id = UUID().uuidString.lowercased()
        let video = resolved.video
        let info = JobInfo(
            jobId: id, status: .queued, videoId: video.id, title: video.title,
            channel: video.channel, duration: video.duration, thumbnail: video.thumbnail,
            sourceUrl: video.sourceUrl, formatId: choice.format.id, formatLabel: choice.format.label,
            height: choice.format.height)
        records[id] = Record(info: info, storedFile: nil)
        queue.append(id)
        log.info("задание \(id, privacy: .public): \(choice.format.label, privacy: .public)")
        persist()
        pump()
        return info
    }

    public func job(_ id: String) -> JobInfo? { records[id]?.info }

    public func list() -> [JobInfo] {
        records.values.map(\.info).sorted { $0.createdAt > $1.createdAt }
    }

    /// Готовый файл, если он есть на диске.
    public func file(_ id: String) -> (url: URL, name: String)? {
        guard let record = records[id], record.info.status == .ready,
              let stored = record.storedFile else { return nil }
        let url = filesDirectory.appendingPathComponent(stored)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url, record.info.filename ?? stored)
    }

    public func cancel(_ id: String) {
        guard let record = records[id], !record.info.status.isFinished else { return }
        if let index = queue.firstIndex(of: id) {
            queue.remove(at: index)
            update(id) { $0.status = .cancelled; $0.progress = nil }
            return
        }
        engines[id]?.cancel()
        running[id]?.cancel()
        // Процесс остановится за доли секунды, но iPhone должен сразу увидеть итог.
        update(id) { $0.status = .cancelled; $0.progress = nil; $0.speed = nil; $0.eta = nil }
    }

    /// Убирает задание и его файл. iPhone зовёт это, когда забрал файл себе.
    public func delete(_ id: String) {
        cancel(id)
        if let stored = records[id]?.storedFile {
            try? FileManager.default.removeItem(at: filesDirectory.appendingPathComponent(stored))
        }
        records[id] = nil
        persist()
    }

    /// Ждёт завершения задания — для фоновой загрузки на iPhone, которая ставится заранее.
    public func waitUntilFinished(_ id: String, timeout: TimeInterval) async -> JobInfo? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let info = records[id]?.info else { return nil }
            if info.status.isFinished { return info }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return records[id]?.info
    }

    // MARK: - выполнение

    private func pump() {
        while running.count < config.maxConcurrent, !queue.isEmpty {
            let id = queue.removeFirst()
            let engine = makeEngine()
            engines[id] = engine
            running[id] = Task { [weak self] in await self?.run(id, engine: engine) }
        }
    }

    private func run(_ id: String, engine: any MediaEngine) async {
        defer { finish(id) }
        guard let record = records[id] else { return }
        let work = config.directory.appendingPathComponent("work/\(id)", isDirectory: true)

        do {
            // Разбор мог устареть, пока задание стояло в очереди.
            update(id) { $0.status = .resolving; $0.progress = nil }
            let resolved = try await resolveCached(url: record.info.sourceUrl)
            guard let choice = resolved.choices.first(where: { $0.format.id == record.info.formatId }) else {
                throw APIErrorBody(.formatUnavailable)
            }
            try checkSpace(for: choice)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            // Перед скачиванием yt-dlp ещё раз разбирает страницу — секунд десять это «подготовка»,
            // а не «скачивание 0 %». Этап сменят события движка, когда пойдут байты.
            let downloaded = try await engine.download(
                plan: choice.plan, url: resolved.resolvedURL, directory: work, baseName: "media",
                onEvent: { [weak self] event in
                    Task { await self?.handle(event, for: id) }
                })
            try Task.checkCancellation()

            var final = downloaded.file
            if let spec = choice.transcode {
                update(id) { $0.status = .transcoding; $0.progress = 0; $0.speed = nil; $0.eta = nil }
                let output = work.appendingPathComponent("final.mp4")
                try await engine.transcode(input: downloaded.file, output: output, spec: spec,
                                           duration: resolved.video.duration,
                                           onProgress: { [weak self] value in
                    Task { await self?.progress(value, for: id) }
                })
                final = output
            }
            try Task.checkCancellation()

            let stored = "\(id).\(choice.finalExtension)"
            let destination = filesDirectory.appendingPathComponent(stored)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: final, to: destination)
            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? nil

            records[id]?.storedFile = stored
            update(id) {
                $0.status = .ready
                $0.progress = 1
                $0.fileSize = size
                $0.downloadedBytes = size
                $0.totalBytes = size
                $0.speed = nil
                $0.eta = nil
                $0.filename = Fmt.safeFileName($0.title) + " [\($0.formatLabel)].\(choice.finalExtension)"
            }
            log.info("задание \(id, privacy: .public) готово")
        } catch is CancellationError {
            update(id) { $0.status = .cancelled; $0.progress = nil }
        } catch let error as YTVDError where error == .cancelled {
            update(id) { $0.status = .cancelled; $0.progress = nil }
        } catch where records[id]?.info.status == .cancelled {
            // Отменили, а движок упал по-своему, пока его останавливали, — это всё равно отмена.
        } catch {
            let body = Self.apiError(from: error)
            // Техническая причина — в журнал, пользователю — человеческий текст.
            log.error("задание \(id, privacy: .public): \(String(describing: error), privacy: .public)")
            update(id) { $0.status = .failed; $0.error = body; $0.progress = nil }
        }
        try? FileManager.default.removeItem(at: work)
    }

    private func finish(_ id: String) {
        running[id] = nil
        engines[id] = nil
        lastProgressAt[id] = nil
        persist()
        pump()
    }

    private func handle(_ event: MediaService.Event, for id: String) {
        guard let status = records[id]?.info.status, !status.isFinished else { return }
        switch event {
        case .phase(let phase):
            let next: JobStatus
            switch phase {
            case "видео": next = .downloadingVideo
            case "аудио": next = .downloadingAudio
            case "склейка", "перекодирование", "обложка в теги": next = .merging
            default: return
            }
            update(id) {
                $0.status = next
                // Склейка идёт без понятного прогресса — пусть iPhone покажет крутилку, а не «100 %».
                $0.progress = next == .merging ? nil : 0
                if next == .merging { $0.speed = nil; $0.eta = nil }
            }
        case .progress(let value):
            // Байты пошли, а строки с именем файла не было — этап всё равно уже скачивание.
            if status == .resolving {
                let audioOnly = records[id]?.info.formatId == IPhoneFormats.audioId
                update(id) { $0.status = audioOnly ? .downloadingAudio : .downloadingVideo }
            }
            // yt-dlp шлёт прогресс очень часто — iPhone незачем столько.
            let now = Date()
            if let last = lastProgressAt[id], now.timeIntervalSince(last) < 0.3 { return }
            lastProgressAt[id] = now
            update(id, save: false) {
                $0.progress = value.fraction
                $0.downloadedBytes = value.downloaded
                $0.totalBytes = value.total
                $0.speed = value.speed
                $0.eta = value.eta
            }
        }
    }

    private func progress(_ value: Double, for id: String) {
        guard let status = records[id]?.info.status, !status.isFinished else { return }
        let now = Date()
        if let last = lastProgressAt[id], now.timeIntervalSince(last) < 0.3, value < 1 { return }
        lastProgressAt[id] = now
        update(id, save: false) { $0.progress = value }
    }

    private func update(_ id: String, save: Bool = true, _ change: (inout JobInfo) -> Void) {
        guard var record = records[id] else { return }
        change(&record.info)
        record.info.updatedAt = Date()
        records[id] = record
        if save { persist() }
    }

    /// Места нужно на видео, звук и склеенный файл, а при перекодировании — ещё на итог.
    private func checkSpace(for choice: FormatChoice) throws {
        guard let free = freeSpace(config.directory) else { return }
        let expected = choice.format.estimatedSize ?? 2 * 1024 * 1024 * 1024
        let factor = choice.transcode == nil ? 2.2 : 3.2
        let needed = Int64(Double(expected) * factor)
        if free < needed {
            throw APIErrorBody(.notEnoughStorage,
                               "На Mac не хватает места: нужно около \(Fmt.bytes(needed)), "
                               + "свободно \(Fmt.bytes(free))")
        }
    }

    // MARK: - хранение

    private func persist() {
        let list = Array(records.values)
        guard let data = try? API.encoder.encode(list) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func restore(from config: Configuration, retention: TimeInterval) -> [String: Record] {
        let fm = FileManager.default
        let index = config.directory.appendingPathComponent("index.json")
        let files = config.directory.appendingPathComponent("files")
        guard let data = try? Data(contentsOf: index),
              let list = try? API.decoder.decode([Record].self, from: data) else { return [:] }

        var restored: [String: Record] = [:]
        let now = Date()
        for var record in list {
            let fileURL = record.storedFile.map { files.appendingPathComponent($0) }

            // Старое, которое iPhone так и не забрал, — удаляем вместе с файлом.
            if now.timeIntervalSince(record.info.updatedAt) > retention {
                if let fileURL { try? fm.removeItem(at: fileURL) }
                continue
            }
            if !record.info.status.isFinished {
                record.info.status = .interrupted
                record.info.progress = nil
                record.info.error = APIErrorBody(.serverError, "Сервер перезапустился посреди работы — "
                                                 + "начните скачивание заново")
            } else if record.info.status == .ready,
                      fileURL.map({ !fm.fileExists(atPath: $0.path) }) ?? true {
                record.info.status = .interrupted
                record.info.error = APIErrorBody(.jobNotFound, "Файл на Mac удалён — скачайте заново")
            }
            restored[record.info.jobId] = record
        }
        return restored
    }

    // MARK: - вспомогательное

    public static let availableSpace: @Sendable (URL) -> Int64? = { url in
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public static let probeThumbnail: @Sendable (String) async -> Bool = { raw in
        guard let url = URL(string: raw) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// Переводит ошибку движка в код для iPhone. Текст уже человеческий — его сохраняем.
    public static func apiError(from error: Error) -> APIErrorBody {
        if let body = error as? APIErrorBody { return body }
        guard let error = error as? YTVDError else {
            return APIErrorBody(.serverError, error.localizedDescription)
        }
        switch error {
        case .cancelled: return APIErrorBody(.cancelled)
        case .network(let message): return APIErrorBody(.networkError, message)
        case .toolMissing(let name): return APIErrorBody(.serverError, "На Mac не найден \(name)")
        case .engineStale(let message): return APIErrorBody(.engineOutdated, message)
        case .tool(let message):
            let lowered = message.lowercased()
            let rules: [(String, APIErrorCode)] = [
                ("приватное", .privateVideo), ("возрастное", .ageRestricted),
                ("недоступно", .videoUnavailable), ("ограничил доступ", .videoUnavailable),
                ("cookies", .authenticationRequired), ("вход", .authenticationRequired),
                ("не робот", .authenticationRequired),
                ("vpn", .blocked), ("адрес", .blocked), ("регионе", .blocked),
                ("места", .notEnoughStorage), ("перекодировать", .ffmpegError),
                ("ffmpeg", .ffmpegError), ("формат", .formatUnavailable),
                ("качество", .formatUnavailable), ("связи", .networkError),
                ("не поддерживается", .invalidUrl),
            ]
            let code = rules.first { lowered.contains($0.0) }?.1 ?? .serverError
            return APIErrorBody(code, message)
        }
    }
}
