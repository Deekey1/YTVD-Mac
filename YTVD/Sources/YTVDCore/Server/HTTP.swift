import Foundation

/// Разобранный HTTP-запрос.
public struct HTTPRequest: Sendable {
    public var method: String
    /// Путь без строки запроса, с раскодированными %XX.
    public var path: String
    public var query: [String: String]
    /// Имена заголовков — в нижнем регистре.
    public var headers: [String: String]
    public var body: Data
    public var remoteAddress: String?

    public init(method: String, path: String, query: [String: String] = [:],
                headers: [String: String] = [:], body: Data = Data(), remoteAddress: String? = nil) {
        self.method = method; self.path = path; self.query = query
        self.headers = headers; self.body = body; self.remoteAddress = remoteAddress
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }
}

/// Тело ответа: данные в памяти или кусок файла, который отдаётся потоком.
public enum HTTPBody: Sendable {
    case empty
    case data(Data)
    /// Файл отдаётся по частям с диска — в память целиком не читается.
    case file(URL, offset: Int64, length: Int64)
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [(String, String)]
    public var body: HTTPBody

    public init(status: Int, headers: [(String, String)] = [], body: HTTPBody = .empty) {
        self.status = status; self.headers = headers; self.body = body
    }

    public static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let data = (try? API.encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status,
                            headers: [("Content-Type", "application/json; charset=utf-8")],
                            body: .data(data))
    }

    public static func error(_ status: Int, _ body: APIErrorBody) -> HTTPResponse {
        json(APIErrorEnvelope(error: body), status: status)
    }

    public static func error(_ status: Int, _ code: APIErrorCode, _ message: String? = nil) -> HTTPResponse {
        error(status, APIErrorBody(code, message))
    }

    public var contentLength: Int64 {
        switch body {
        case .empty: 0
        case .data(let data): Int64(data.count)
        case .file(_, _, let length): length
        }
    }

    /// Заголовки ответа целиком, включая строку статуса.
    public func head(includeBody: Bool = true) -> Data {
        var lines = ["HTTP/1.1 \(status) \(Self.reason(status))"]
        var names = Set<String>()
        for (name, value) in headers {
            lines.append("\(name): \(value)")
            names.insert(name.lowercased())
        }
        if !names.contains("content-length") { lines.append("Content-Length: \(contentLength)") }
        // Каждое соединение — один запрос: проще и надёжнее, URLSession к этому готов.
        lines.append("Connection: close")
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 204: "No Content"
        case 206: "Partial Content"
        case 304: "Not Modified"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 413: "Payload Too Large"
        case 416: "Range Not Satisfiable"
        case 422: "Unprocessable Content"
        case 425: "Too Early"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        case 504: "Gateway Timeout"
        case 507: "Insufficient Storage"
        default: "Status"
        }
    }
}

// MARK: - разбор запроса

public enum HTTPParser {

    public static let maxHeaderBytes = 32 * 1024
    public static let maxBodyBytes = 1 * 1024 * 1024

    public enum Result: Equatable {
        /// Запрос пришёл не целиком — надо дочитать.
        case needMore
        case complete(consumed: Int)
        case invalid(status: Int)
    }

    /// Проверяет, пришёл ли запрос целиком, и если да — сколько байт он занимает.
    public static func check(_ buffer: Data) -> Result {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxHeaderBytes ? .invalid(status: 431) : .needMore
        }
        let headerLength = headerEnd.upperBound - buffer.startIndex
        guard headerLength <= maxHeaderBytes else { return .invalid(status: 431) }

        let headerText = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var length = 0
        for line in headerText.split(separator: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            guard let value = Int(parts[1].trimmingCharacters(in: .whitespaces)), value >= 0 else {
                return .invalid(status: 400)
            }
            length = value
        }
        guard length <= maxBodyBytes else { return .invalid(status: 413) }
        return buffer.count >= headerLength + length ? .complete(consumed: headerLength + length) : .needMore
    }

    /// Разбирает целиком пришедший запрос.
    public static func parse(_ buffer: Data) -> HTTPRequest? {
        guard case .complete(let consumed) = check(buffer),
              let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }

        let headerText = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespaces)
        }

        let target = String(requestLine[1])
        let components = URLComponents(string: "http://localhost" + (target.hasPrefix("/") ? target : "/" + target))
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }

        let bodyStart = headerEnd.upperBound
        let bodyEnd = buffer.startIndex + consumed
        return HTTPRequest(method: String(requestLine[0]).uppercased(),
                           path: components?.path ?? target,
                           query: query, headers: headers,
                           body: bodyStart < bodyEnd ? Data(buffer[bodyStart..<bodyEnd]) : Data())
    }
}

// MARK: - Range-запросы

public enum ByteRange {

    public enum Result: Equatable {
        /// Заголовка нет или его надо проигнорировать — отдаём целиком.
        case full
        case partial(offset: Int64, length: Int64)
        case unsatisfiable
    }

    /// Понимает «bytes=A-B», «bytes=A-» и «bytes=-N». Несколько диапазонов сразу не поддерживаем —
    /// отдаём файл целиком, это допустимо по RFC 9110.
    public static func parse(_ header: String?, size: Int64) -> Result {
        guard let header, header.lowercased().hasPrefix("bytes=") else { return .full }
        let spec = header.dropFirst("bytes=".count).trimmingCharacters(in: .whitespaces)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return .full }

        let startText = spec[spec.startIndex..<dash].trimmingCharacters(in: .whitespaces)
        let endText = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)

        if startText.isEmpty {
            // Последние N байт.
            guard let suffix = Int64(endText), suffix > 0 else { return .unsatisfiable }
            let length = min(suffix, size)
            return size == 0 ? .unsatisfiable : .partial(offset: size - length, length: length)
        }
        guard let start = Int64(startText), start >= 0 else { return .full }
        guard start < size else { return .unsatisfiable }

        var end = size - 1
        if !endText.isEmpty {
            guard let value = Int64(endText), value >= start else { return .unsatisfiable }
            end = min(value, size - 1)
        }
        return .partial(offset: start, length: end - start + 1)
    }
}
