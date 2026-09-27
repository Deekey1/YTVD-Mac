import XCTest
@testable import YTVDCore

/// Настоящий обмен через сокет: URLSession ↔ HTTPServer на 127.0.0.1.
final class LoopbackTests: BackendTestCase {

    private var server: BackendServer!
    private var shared: FakeEngine.Shared!
    private var base: URL!
    private let session = URLSession(configuration: .ephemeral)

    override func setUp() async throws {
        shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        server = makeServer(shared)
        try server.start(port: 0, bind: .loopback)

        for _ in 0..<200 {
            if case .listening(let port) = server.state {
                base = URL(string: "http://127.0.0.1:\(port)\(API.basePath)")!
                return
            }
            if case .failed(let reason) = server.state { XCTFail(reason); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("сервер не запустился")
    }

    override func tearDown() {
        server?.stop()
    }

    private func send(_ method: String, _ path: String, token: String? = nil, json: (any Encodable)? = nil,
                      headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json {
            request.httpBody = try API.encoder.encode(json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    func testInfoAndAuthOverSocket() async throws {
        let (data, response) = try await send("GET", "info")
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        XCTAssertEqual(try API.decoder.decode(ServerInfo.self, from: data).name, "Тестовый Mac")

        let (errorData, denied) = try await send("GET", "jobs")
        XCTAssertEqual(denied.statusCode, 401)
        XCTAssertEqual(try API.decoder.decode(APIErrorEnvelope.self, from: errorData).error.code, "unauthorized")
    }

    func testPairResolveDownloadAndResumeOverSocket() async throws {
        shared.fileBytes = 3_000_000       // больше куска в 256 КБ — проверяем потоковую отдачу
        let expected = FakeEngine.pattern(shared.fileBytes)

        let (code, _) = server.pairing.newCode()
        let (pairData, _) = try await send("POST", "pair", json: PairRequest(code: code, deviceName: "iPhone"))
        let token = try API.decoder.decode(PairResponse.self, from: pairData).token

        let (videoData, resolved) = try await send("POST", "resolve", token: token, json: ResolveRequest(url: url))
        XCTAssertEqual(resolved.statusCode, 200)
        XCTAssertEqual(try API.decoder.decode(VideoInfo.self, from: videoData).recommendedFormatId, "h1080-60")

        let (jobData, accepted) = try await send("POST", "download", token: token,
                                                 json: DownloadRequest(url: url, formatId: "h1080-60"))
        XCTAssertEqual(accepted.statusCode, 202)
        let job = try API.decoder.decode(JobInfo.self, from: jobData)
        _ = try await waitReady(server, job.jobId, token: token)

        let (file, full) = try await send("GET", "jobs/\(job.jobId)/file", token: token)
        XCTAssertEqual(full.statusCode, 200)
        XCTAssertEqual(full.expectedContentLength, Int64(expected.count))
        XCTAssertEqual(file, expected, "файл дошёл байт в байт")

        let etag = try XCTUnwrap(full.value(forHTTPHeaderField: "ETag"))
        let (tail, partial) = try await send("GET", "jobs/\(job.jobId)/file", token: token,
                                             headers: ["Range": "bytes=1000000-", "If-Range": etag])
        XCTAssertEqual(partial.statusCode, 206)
        XCTAssertEqual(partial.value(forHTTPHeaderField: "Content-Range"), "bytes 1000000-2999999/3000000")
        XCTAssertEqual(tail, expected.subdata(in: 1_000_000..<3_000_000))

        let (headBody, head) = try await send("HEAD", "jobs/\(job.jobId)/file", token: token)
        XCTAssertEqual(head.statusCode, 200)
        XCTAssertEqual(head.value(forHTTPHeaderField: "Content-Length"), "3000000")
        XCTAssertTrue(headBody.isEmpty, "на HEAD тела нет")
    }

    func testManyParallelRequests() async throws {
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<24 {
                group.addTask { try await self.send("GET", "info").1.statusCode }
            }
            for try await status in group { XCTAssertEqual(status, 200) }
        }
    }

    func testMalformedRequestGets400() async throws {
        guard case .listening(let port) = server.state else { return XCTFail() }
        let reply = try await rawExchange(port: port, "BROKEN\r\n\r\n")
        XCTAssertTrue(reply.hasPrefix("HTTP/1.1 400"), reply)
    }

    /// Сырой обмен через сокет — чтобы послать то, что URLSession послать не даст.
    private func rawExchange(port: UInt16, _ text: String) async throws -> String {
        try await Task.detached {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            defer { close(fd) }
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard connected == 0 else { throw URLError(.cannotConnectToHost) }
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            _ = text.withCString { Darwin.send(fd, $0, strlen($0), 0) }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = recv(fd, &buffer, buffer.count, 0)
            return String(decoding: buffer.prefix(max(0, count)), as: UTF8.self)
        }.value
    }
}
