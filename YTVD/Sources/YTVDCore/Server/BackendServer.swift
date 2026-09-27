import Foundation
import os

/// Сервер для iPhone: REST API поверх того же движка, что у Mac-приложения.
///
/// Маршрутизатор отделён от сети (`handle`), поэтому весь API проверяется тестами
/// без открытия сокетов, а HTTPServer отвечает только за байты.
public final class BackendServer: @unchecked Sendable {

    public let store: JobStore
    public let pairing: PairingManager
    public let name: String
    public let appVersion: String

    private let engineProbe: @Sendable () -> any MediaEngine
    private let freeSpace: @Sendable () -> Int64?
    private let log = Logger(subsystem: "studio.dk.ytvd", category: "api")
    private var http: HTTPServer?

    /// Сколько держать фоновый запрос файла, пока Mac ещё качает.
    public static let longPollLimit: TimeInterval = 25 * 60

    /// Обновление yt-dlp по просьбе iPhone. Нет — значит, сервер этого не умеет.
    public var engineUpdate: (@Sendable () async throws -> EngineUpdateResult)?
    private let updateLock = NSLock()
    private var updating = false

    public init(store: JobStore, pairing: PairingManager, name: String, appVersion: String,
                engineProbe: @escaping @Sendable () -> any MediaEngine,
                freeSpace: @escaping @Sendable () -> Int64? = { nil }) {
        self.store = store
        self.pairing = pairing
        self.name = name
        self.appVersion = appVersion
        self.engineProbe = engineProbe
        self.freeSpace = freeSpace
    }

    // MARK: - сеть

    public var onStateChange: (@Sendable (HTTPServer.State) -> Void)?
    /// iPhone ввёл верный код — окно на Mac может убрать код и сказать, кто подключился.
    public var onPaired: (@Sendable (String) -> Void)?

    public func start(port: UInt16, bind: BindAddress) throws {
        stop()
        let server = HTTPServer(port: port, bind: bind, bonjourName: name,
                                bonjourTXT: ["api": API.version, "app": appVersion]) { [weak self] request in
            guard let self else { return .error(503, .serverError) }
            return await self.handle(request)
        }
        server.onStateChange = { [weak self] state in self?.onStateChange?(state) }
        try server.start()
        http = server
    }

    public func stop() {
        http?.stop()
        http = nil
    }

    public var state: HTTPServer.State { http?.state ?? .stopped }

    // MARK: - маршрутизация

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let started = Date()
        let response = await route(request)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        // Ни токена, ни тела запроса в журнал: только метод, путь и итог.
        log.info("\(request.method, privacy: .public) \(request.path, privacy: .public) → \(response.status) за \(ms) мс")
        return response
    }

    private func route(_ request: HTTPRequest) async -> HTTPResponse {
        let base = API.basePath
        guard request.path.hasPrefix(base) else { return .error(404, .badRequest, "Нет такого адреса") }
        let parts = request.path.dropFirst(base.count).split(separator: "/").map(String.init)
        let method = request.method

        /// Сопоставление с образцом пути: «:имя» — параметр. Возвращает параметры по порядку.
        func match(_ pattern: String...) -> [String]? {
            guard parts.count == pattern.count else { return nil }
            var captured: [String] = []
            for (part, expected) in zip(parts, pattern) {
                if expected.hasPrefix(":") { captured.append(part) }
                else if part != expected { return nil }
            }
            return captured
        }

        // Без токена доступны только сведения о сервере и сопряжение.
        if method == "GET", match("info") != nil {
            return info(authorized: pairing.isAuthorized(request.header("authorization")))
        }
        if method == "POST", match("pair") != nil {
            return pair(request)
        }

        let known = match("resolve") ?? match("download") ?? match("jobs") ?? match("engine", "update")
            ?? match("jobs", ":id") ?? match("jobs", ":id", "file") ?? match("jobs", ":id", "cancel")
        guard known != nil else { return .error(404, .badRequest, "Нет такого адреса") }

        guard pairing.isAuthorized(request.header("authorization")) else {
            return .error(401, .unauthorized)
        }

        if method == "POST", match("resolve") != nil { return await resolve(request) }
        if method == "POST", match("download") != nil { return await download(request) }
        if method == "GET", match("jobs") != nil { return .json(JobList(jobs: await store.list())) }
        if method == "POST", match("engine", "update") != nil { return await updateEngine() }

        if let id = match("jobs", ":id")?.first {
            switch method {
            case "GET":
                guard let job = await store.job(id) else { return .error(404, .jobNotFound) }
                return .json(job)
            case "DELETE":
                await store.delete(id)
                return HTTPResponse(status: 204)
            default:
                break
            }
        }
        if method == "POST", let id = match("jobs", ":id", "cancel")?.first {
            await store.cancel(id)
            guard let job = await store.job(id) else { return .error(404, .jobNotFound) }
            return .json(job)
        }
        if method == "GET" || method == "HEAD", let id = match("jobs", ":id", "file")?.first {
            return await file(id, request: request)
        }
        return .error(405, .badRequest, "Этот метод здесь не поддерживается")
    }

    // MARK: - обработчики

    private func info(authorized: Bool) -> HTTPResponse {
        let engine = engineProbe()
        var info = ServerInfo(name: name, appVersion: appVersion, apiVersion: API.version,
                              authorized: authorized, ready: engine.versions.ytdlp != nil)
        // Версии инструментов и свободное место — только своим.
        if authorized {
            info.ytdlpVersion = engine.versions.ytdlp
            info.ffmpegVersion = engine.versions.ffmpeg
            info.jsRuntime = engine.versions.js
            info.freeSpace = freeSpace()
        }
        return .json(info)
    }

    private func pair(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = try? API.decoder.decode(PairRequest.self, from: request.body) else {
            return .error(400, .badRequest, "Ожидался код сопряжения")
        }
        switch pairing.pair(code: body.code) {
        case .success(let token):
            log.info("сопряжено устройство «\(body.deviceName, privacy: .public)»")
            onPaired?(body.deviceName)
            return .json(PairResponse(token: token, serverName: name))
        case .invalid:
            return .error(403, .pairingFailed)
        case .expired:
            return .error(403, .pairingFailed, "Код устарел — покажите на Mac новый")
        }
    }

    private func resolve(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? API.decoder.decode(ResolveRequest.self, from: request.body) else {
            return .error(400, .badRequest, "Ожидалась ссылка")
        }
        do {
            return .json(try await store.resolve(url: body.url))
        } catch {
            return failure(JobStore.apiError(from: error))
        }
    }

    private func download(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = try? API.decoder.decode(DownloadRequest.self, from: request.body) else {
            return .error(400, .badRequest, "Ожидались ссылка и вариант качества")
        }
        do {
            return .json(try await store.startDownload(url: body.url, formatId: body.formatId), status: 202)
        } catch {
            return failure(JobStore.apiError(from: error))
        }
    }

    private func updateEngine() async -> HTTPResponse {
        guard let engineUpdate else {
            return .error(501, .serverError, "Этот сервер не умеет обновлять движок")
        }
        guard beginUpdate() else {
            return .error(409, .serverError, "Движок уже обновляется — подождите минуту")
        }
        defer { endUpdate() }

        do {
            let result = try await engineUpdate()
            log.info("движок: \(result.message, privacy: .public)")
            return .json(result)
        } catch {
            log.error("обновление движка: \(String(describing: error), privacy: .public)")
            let message = (error as? YTVDError)?.errorDescription ?? error.localizedDescription
            return .error(502, .networkError, "Не удалось обновить движок: \(message)")
        }
    }

    /// Два обновления сразу ни к чему: второе просто ждало бы первое.
    private func beginUpdate() -> Bool {
        updateLock.withLock {
            guard !updating else { return false }
            updating = true
            return true
        }
    }

    private func endUpdate() { updateLock.withLock { updating = false } }

    private func file(_ id: String, request: HTTPRequest) async -> HTTPResponse {
        guard var job = await store.job(id) else { return .error(404, .jobNotFound) }

        // Фоновая загрузка на iPhone ставится заранее и ждёт, пока Mac докачает.
        if !job.status.isFinished, request.query["wait"] == "1" {
            job = await store.waitUntilFinished(id, timeout: Self.longPollLimit) ?? job
        }
        switch job.status {
        case .ready:
            break
        case .failed, .cancelled, .interrupted:
            return failure(job.error ?? APIErrorBody(.cancelled))
        default:
            return .error(409, .notReady)
        }
        guard let (url, name) = await store.file(id),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return .error(404, .jobNotFound, "Файл на Mac не найден")
        }

        let modified = (attributes[.modificationDate] as? Date) ?? Date()
        let etag = "\"\(size)-\(Int(modified.timeIntervalSince1970))\""
        var headers: [(String, String)] = [
            ("Content-Type", url.pathExtension == "m4a" ? "audio/mp4" : "video/mp4"),
            ("Accept-Ranges", "bytes"),
            ("ETag", etag),
            ("Last-Modified", Self.httpDate(modified)),
            ("Content-Disposition", Self.disposition(name)),
        ]

        // If-Range: докачка допустима, только если файл тот же самый.
        var rangeHeader = request.header("range")
        if let ifRange = request.header("if-range"), ifRange != etag { rangeHeader = nil }

        switch ByteRange.parse(rangeHeader, size: size) {
        case .full:
            return HTTPResponse(status: 200, headers: headers, body: .file(url, offset: 0, length: size))
        case .partial(let offset, let length):
            headers.append(("Content-Range", "bytes \(offset)-\(offset + length - 1)/\(size)"))
            return HTTPResponse(status: 206, headers: headers, body: .file(url, offset: offset, length: length))
        case .unsatisfiable:
            return HTTPResponse(status: 416, headers: [("Content-Range", "bytes */\(size)")])
        }
    }

    // MARK: - вспомогательное

    private func failure(_ body: APIErrorBody) -> HTTPResponse {
        .error(Self.status(for: body.code), body)
    }

    /// HTTP-статус по коду ошибки API.
    static func status(for code: String) -> Int {
        switch APIErrorCode(rawValue: code) {
        case .badRequest, .invalidUrl: 400
        case .unauthorized: 401
        case .pairingFailed: 403
        case .jobNotFound: 404
        case .notReady: 409
        case .formatUnavailable, .videoUnavailable, .privateVideo, .ageRestricted,
             .authenticationRequired, .blocked: 422
        case .rateLimited: 429
        case .networkError: 502
        case .engineOutdated: 503
        case .notEnoughStorage: 507
        case .cancelled: 409
        case .ffmpegError, .serverError, .none: 500
        }
    }

    /// Имя файла для «Сохранить как»: ASCII-запасное плюс настоящее в UTF-8 (RFC 6266).
    static func disposition(_ name: String) -> String {
        let ascii = String(name.unicodeScalars.map { $0.isASCII && $0 != "\"" ? Character($0) : "_" })
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: ".-_"))) ?? ascii
        return "attachment; filename=\"\(ascii)\"; filename*=UTF-8''\(encoded)"
    }

    static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}
