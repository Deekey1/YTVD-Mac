import Foundation
import os
import YTVDAPI

/// Клиент REST API сервера на Mac. О yt-dlp ничего не знает — только контракт YTVDAPI,
/// поэтому сервер можно будет перенести на VPS, не трогая приложение.
struct APIClient: Sendable {

    let baseURL: URL
    let token: String?

    private static let log = Logger(subsystem: "studio.dk.videodownloader", category: "api")

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Разбор ссылки на Mac занимает до десятка секунд — не обрываем его раньше времени.
        config.timeoutIntervalForRequest = 90
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - методы API

    func info() async throws -> ServerInfo {
        try await send(request("GET", "/info", timeout: 5))
    }

    func pair(code: String, deviceName: String) async throws -> PairResponse {
        try await send(request("POST", "/pair", body: PairRequest(code: code, deviceName: deviceName), timeout: 10))
    }

    func resolve(_ url: String) async throws -> VideoInfo {
        try await send(request("POST", "/resolve", body: ResolveRequest(url: url)))
    }

    func startDownload(url: String, formatId: String) async throws -> JobInfo {
        try await send(request("POST", "/download", body: DownloadRequest(url: url, formatId: formatId)))
    }

    func job(_ id: String) async throws -> JobInfo {
        try await send(request("GET", "/jobs/\(id)", timeout: 10))
    }

    func cancel(_ id: String) async throws {
        _ = try await perform(request("POST", "/jobs/\(id)/cancel", timeout: 10))
    }

    func delete(_ id: String) async throws {
        _ = try await perform(request("DELETE", "/jobs/\(id)", timeout: 10))
    }

    /// Обновление yt-dlp на Mac. Исполняемый код меняется только там — не в приложении.
    func updateEngine() async throws -> EngineUpdateResult {
        try await send(request("POST", "/engine/update", timeout: 300))
    }

    /// Запрос файла для фоновой загрузки. С wait=1 сервер держит запрос, пока Mac не докачает,
    /// поэтому загрузку можно поставить сразу — и она переживёт блокировку экрана.
    func fileRequest(jobId: String) -> URLRequest {
        var components = URLComponents(url: endpoint("/jobs/\(jobId)/file"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "wait", value: "1")]
        var request = URLRequest(url: components.url!)
        authorize(&request)
        request.timeoutInterval = 30 * 60
        return request
    }

    // MARK: - запросы

    private func endpoint(_ path: String) -> URL {
        baseURL.appending(path: API.basePath + path)
    }

    private func authorize(_ request: inout URLRequest) {
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.allowsCellularAccess = !Prefs.wifiOnlyEnabled
    }

    private func request(_ method: String, _ path: String, body: (any Encodable)? = nil,
                         timeout: TimeInterval? = nil) throws -> URLRequest {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        authorize(&request)
        if let body {
            request.httpBody = try API.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let timeout { request.timeoutInterval = timeout }
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await perform(request)
        do {
            return try API.decoder.decode(T.self, from: data)
        } catch {
            Self.log.error("не разобран ответ \(request.url?.path ?? "", privacy: .public): \(error, privacy: .public)")
            throw AppError.network("Mac ответил непонятно — возможно, версии YTVD и приложения разошлись")
        }
    }

    @discardableResult
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let started = Date()
        let label = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        let data: Data
        let http: HTTPURLResponse
        do {
            let (body, response) = try await Self.session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw AppError.network("Непонятный ответ от Mac")
            }
            data = body
            http = response
        } catch {
            // Токен в журнал не попадает: только метод, путь и причина.
            Self.log.error("\(label, privacy: .public): \(String(describing: error), privacy: .public)")
            throw AppError.from(error)
        }

        let ms = Int(Date().timeIntervalSince(started) * 1000)
        Self.log.info("\(label, privacy: .public) → \(http.statusCode) за \(ms) мс")
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? API.decoder.decode(APIErrorEnvelope.self, from: data) {
                throw AppError.from(envelope.error)
            }
            throw http.statusCode == 401 ? AppError.unauthorized
                : AppError.network("Mac ответил ошибкой \(http.statusCode)")
        }
        return (data, http)
    }

    // MARK: - адрес

    /// Адрес, введённый руками: «192.168.1.10», «macbook.local:8765», «http://…».
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text),
              let host = components.host, !host.isEmpty,
              components.scheme == "http" || components.scheme == "https" else { return nil }
        if components.port == nil { components.port = Int(API.defaultPort) }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }
}
