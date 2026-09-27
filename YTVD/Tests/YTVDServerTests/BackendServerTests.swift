import XCTest
@testable import YTVDCore

/// Общие помощники: сервер на подставном движке и вызовы API без сети.
class BackendTestCase: XCTestCase {

    let url = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"

    func makeServer(_ shared: FakeEngine.Shared) -> BackendServer {
        let directory = Fixtures.temporaryDirectory()
        let store = JobStore(config: .init(directory: directory.appendingPathComponent("jobs")),
                             makeEngine: { FakeEngine(shared) },
                             freeSpace: { _ in nil },
                             thumbnailProbe: { _ in true })
        return BackendServer(store: store, pairing: PairingManager(directory: directory),
                             name: "Тестовый Mac", appVersion: "9.9",
                             engineProbe: { FakeEngine(shared) }, freeSpace: { 123_456 })
    }

    func call(_ server: BackendServer, _ method: String, _ path: String, token: String? = nil,
              json: (any Encodable)? = nil, headers: [String: String] = [:],
              query: [String: String] = [:]) async -> HTTPResponse {
        var all = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        if let token { all["authorization"] = "Bearer \(token)" }
        let body = json.flatMap { try? API.encoder.encode($0) } ?? Data()
        return await server.handle(HTTPRequest(method: method, path: API.basePath + path,
                                               query: query, headers: all, body: body))
    }

    func decode<T: Decodable>(_ type: T.Type, _ response: HTTPResponse,
                              file: StaticString = #filePath, line: UInt = #line) throws -> T {
        guard case .data(let data) = response.body else {
            XCTFail("ответ без JSON", file: file, line: line)
            throw CancellationError()
        }
        return try API.decoder.decode(T.self, from: data)
    }

    func errorCode(_ response: HTTPResponse) -> String? {
        try? decode(APIErrorEnvelope.self, response).error.code
    }

    func bytes(_ response: HTTPResponse) throws -> Data {
        switch response.body {
        case .empty: return Data()
        case .data(let data): return data
        case .file(let url, let offset, let length):
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: Int(length)) ?? Data()
        }
    }

    func header(_ response: HTTPResponse, _ name: String) -> String? {
        response.headers.first { $0.0.lowercased() == name.lowercased() }?.1
    }

    func pair(_ server: BackendServer) async throws -> String {
        let (code, _) = server.pairing.newCode()
        let response = await call(server, "POST", "/pair", json: PairRequest(code: code, deviceName: "iPhone"))
        XCTAssertEqual(response.status, 200)
        return try decode(PairResponse.self, response).token
    }

    func waitReady(_ server: BackendServer, _ id: String, token: String) async throws -> JobInfo {
        for _ in 0..<250 {
            let job = try decode(JobInfo.self, await call(server, "GET", "/jobs/\(id)", token: token))
            if job.status.isFinished { return job }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("задание не завершилось")
        throw CancellationError()
    }
}

final class BackendServerTests: BackendTestCase {

    func testInfoHidesDetailsWithoutToken() async throws {
        let server = makeServer(FakeEngine.Shared(info: try Fixtures.youtube4K()))

        let anonymous = try decode(ServerInfo.self, await call(server, "GET", "/info"))
        XCTAssertEqual(anonymous.name, "Тестовый Mac")
        XCTAssertEqual(anonymous.apiVersion, API.version)
        XCTAssertFalse(anonymous.authorized)
        XCTAssertNil(anonymous.ytdlpVersion, "версии инструментов чужим не показываем")
        XCTAssertNil(anonymous.freeSpace)

        let token = try await pair(server)
        let mine = try decode(ServerInfo.self, await call(server, "GET", "/info", token: token))
        XCTAssertTrue(mine.authorized)
        XCTAssertEqual(mine.ytdlpVersion, "2026.07.04")
        XCTAssertEqual(mine.freeSpace, 123_456)
    }

    func testEverythingElseNeedsToken() async throws {
        let server = makeServer(FakeEngine.Shared(info: try Fixtures.youtube4K()))
        let calls: [(String, String)] = [
            ("POST", "/resolve"), ("POST", "/download"), ("GET", "/jobs"),
            ("GET", "/jobs/x"), ("DELETE", "/jobs/x"), ("POST", "/jobs/x/cancel"), ("GET", "/jobs/x/file"),
        ]
        for (method, path) in calls {
            let response = await call(server, method, path, json: ResolveRequest(url: url))
            XCTAssertEqual(response.status, 401, "\(method) \(path)")
            XCTAssertEqual(errorCode(response), APIErrorCode.unauthorized.rawValue)

            let wrong = await call(server, method, path, token: "чужой-токен", json: ResolveRequest(url: url))
            XCTAssertEqual(wrong.status, 401, "\(method) \(path) с чужим токеном")
        }
    }

    func testPairing() async throws {
        let server = makeServer(FakeEngine.Shared(info: try Fixtures.youtube4K()))
        let (code, _) = server.pairing.newCode()
        let wrong = code == "000000" ? "111111" : "000000"

        let refused = await call(server, "POST", "/pair", json: PairRequest(code: wrong, deviceName: "iPhone"))
        XCTAssertEqual(refused.status, 403)
        XCTAssertEqual(errorCode(refused), APIErrorCode.pairingFailed.rawValue)

        let garbage = await call(server, "POST", "/pair", json: ResolveRequest(url: "x"))
        XCTAssertEqual(garbage.status, 400)

        let accepted = await call(server, "POST", "/pair", json: PairRequest(code: code, deviceName: "iPhone"))
        let paired = try decode(PairResponse.self, accepted)
        XCTAssertEqual(paired.serverName, "Тестовый Mac")
        XCTAssertEqual(paired.token, server.pairing.token)

        let again = await call(server, "POST", "/pair", json: PairRequest(code: code, deviceName: "iPhone"))
        XCTAssertEqual(again.status, 403, "код одноразовый")
    }

    func testResolve() async throws {
        let server = makeServer(FakeEngine.Shared(info: try Fixtures.youtube4K()))
        let token = try await pair(server)

        let response = await call(server, "POST", "/resolve", token: token, json: ResolveRequest(url: url))
        XCTAssertEqual(response.status, 200)
        let video = try decode(VideoInfo.self, response)
        XCTAssertEqual(video.title, "Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film")
        XCTAssertEqual(video.recommendedFormatId, "h1080-60")
        XCTAssertEqual(video.formats.map(\.id).last, "audio")

        // Ключи в JSON — snake_case: так договорились с iPhone.
        guard case .data(let data) = response.body else { return XCTFail() }
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"recommended_format_id\""))
        XCTAssertTrue(text.contains("\"needs_transcode\""))
        XCTAssertFalse(text.contains("format_id\":\"137"), "номера форматов yt-dlp наружу не уходят")
    }

    func testResolveErrors() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        let server = makeServer(shared)
        let token = try await pair(server)

        let foreign = await call(server, "POST", "/resolve", token: token,
                                 json: ResolveRequest(url: "https://example.com/v"))
        XCTAssertEqual(foreign.status, 400)
        XCTAssertEqual(errorCode(foreign), APIErrorCode.invalidUrl.rawValue)

        let noBody = await call(server, "POST", "/resolve", token: token)
        XCTAssertEqual(noBody.status, 400)
        XCTAssertEqual(errorCode(noBody), APIErrorCode.badRequest.rawValue)

        shared.failResolve = YTVDError.tool("Это приватное видео")
        let hidden = await call(server, "POST", "/resolve", token: token,
                                json: ResolveRequest(url: "https://youtu.be/xxxxxxxxxxx"))
        XCTAssertEqual(hidden.status, 422)
        let body = try decode(APIErrorEnvelope.self, hidden).error
        XCTAssertEqual(body.code, APIErrorCode.privateVideo.rawValue)
        XCTAssertEqual(body.message, "Это приватное видео")
    }

    func testUnknownAddressesAndMethods() async throws {
        let server = makeServer(FakeEngine.Shared(info: try Fixtures.youtube4K()))
        let token = try await pair(server)

        let missing = await call(server, "GET", "/nothing", token: token)
        XCTAssertEqual(missing.status, 404)
        let outside = await server.handle(HTTPRequest(method: "GET", path: "/index.html"))
        XCTAssertEqual(outside.status, 404)
        let wrongMethod = await call(server, "PUT", "/resolve", token: token)
        XCTAssertEqual(wrongMethod.status, 405)
        let unknownJob = await call(server, "GET", "/jobs/nope", token: token)
        XCTAssertEqual(unknownJob.status, 404)
        XCTAssertEqual(errorCode(unknownJob), APIErrorCode.jobNotFound.rawValue)
    }

    func testDownloadAndFetchFileWithRanges() async throws {
        let server = makeServer(FakeEngine.Shared(info: try Fixtures.youtube4K()))
        let token = try await pair(server)

        let accepted = await call(server, "POST", "/download", token: token,
                                  json: DownloadRequest(url: url, formatId: "h1080-60"))
        XCTAssertEqual(accepted.status, 202)
        let job = try decode(JobInfo.self, accepted)
        let ready = try await waitReady(server, job.jobId, token: token)
        XCTAssertEqual(ready.status, .ready)

        let full = await call(server, "GET", "/jobs/\(job.jobId)/file", token: token)
        XCTAssertEqual(full.status, 200)
        XCTAssertEqual(full.contentLength, 4096)
        XCTAssertEqual(try bytes(full), FakeEngine.pattern(4096))
        XCTAssertEqual(header(full, "Content-Type"), "video/mp4")
        XCTAssertEqual(header(full, "Accept-Ranges"), "bytes")
        XCTAssertTrue(header(full, "Content-Disposition")?.contains("filename*=UTF-8''Big%20Buck") == true)
        let etag = try XCTUnwrap(header(full, "ETag"))

        // Докачка с середины — то, чем пользуется фоновая загрузка iPhone после обрыва.
        let part = await call(server, "GET", "/jobs/\(job.jobId)/file", token: token,
                              headers: ["Range": "bytes=1000-", "If-Range": etag])
        XCTAssertEqual(part.status, 206)
        XCTAssertEqual(header(part, "Content-Range"), "bytes 1000-4095/4096")
        XCTAssertEqual(try bytes(part), FakeEngine.pattern(4096).subdata(in: 1000..<4096))

        let stale = await call(server, "GET", "/jobs/\(job.jobId)/file", token: token,
                               headers: ["Range": "bytes=1000-", "If-Range": "\"другой-файл\""])
        XCTAssertEqual(stale.status, 200, "файл сменился — отдаём целиком, а не кусок чужого")

        let beyond = await call(server, "GET", "/jobs/\(job.jobId)/file", token: token,
                                headers: ["Range": "bytes=9000-"])
        XCTAssertEqual(beyond.status, 416)
        XCTAssertEqual(header(beyond, "Content-Range"), "bytes */4096")
    }

    func testFileWaitsForJobWhenAsked() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        shared.released = false
        let server = makeServer(shared)
        let token = try await pair(server)
        let job = try decode(JobInfo.self, await call(server, "POST", "/download", token: token,
                                                      json: DownloadRequest(url: url, formatId: "h720-60")))

        let early = await call(server, "GET", "/jobs/\(job.jobId)/file", token: token)
        XCTAssertEqual(early.status, 409)
        XCTAssertEqual(errorCode(early), APIErrorCode.notReady.rawValue)

        Task { try await Task.sleep(nanoseconds: 300_000_000); shared.released = true }
        let waited = await call(server, "GET", "/jobs/\(job.jobId)/file", token: token, query: ["wait": "1"])
        XCTAssertEqual(waited.status, 200, "с wait=1 сервер дожидается готовности и сразу отдаёт файл")
    }

    func testFailedJobExplainsWhy() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        shared.failDownload = YTVDError.tool("Площадка заблокировала адрес — обычно так отсекают VPN")
        let server = makeServer(shared)
        let token = try await pair(server)
        let job = try decode(JobInfo.self, await call(server, "POST", "/download", token: token,
                                                      json: DownloadRequest(url: url, formatId: "h720-60")))
        let finished = try await waitReady(server, job.jobId, token: token)
        XCTAssertEqual(finished.status, .failed)
        XCTAssertEqual(finished.error?.code, APIErrorCode.blocked.rawValue)

        let file = await call(server, "GET", "/jobs/\(job.jobId)/file", token: token)
        XCTAssertEqual(file.status, 422)
        XCTAssertEqual(errorCode(file), APIErrorCode.blocked.rawValue)
    }

    func testUnknownFormatIs422() async throws {
        let server = makeServer(FakeEngine.Shared(info: try Fixtures.youtube4K()))
        let token = try await pair(server)
        let response = await call(server, "POST", "/download", token: token,
                                  json: DownloadRequest(url: url, formatId: "h9999"))
        XCTAssertEqual(response.status, 422)
        XCTAssertEqual(errorCode(response), APIErrorCode.formatUnavailable.rawValue)
    }

    func testCancelListAndDelete() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        shared.released = false
        let server = makeServer(shared)
        let token = try await pair(server)

        let first = try decode(JobInfo.self, await call(server, "POST", "/download", token: token,
                                                        json: DownloadRequest(url: url, formatId: "h720-60")))
        let second = try decode(JobInfo.self, await call(server, "POST", "/download", token: token,
                                                         json: DownloadRequest(url: url, formatId: "h480")))

        let list = try decode(JobList.self, await call(server, "GET", "/jobs", token: token))
        XCTAssertEqual(Set(list.jobs.map(\.jobId)), [first.jobId, second.jobId])

        let cancelled = try decode(JobInfo.self, await call(server, "POST", "/jobs/\(second.jobId)/cancel", token: token))
        XCTAssertEqual(cancelled.status, .cancelled)

        let deleted = await call(server, "DELETE", "/jobs/\(first.jobId)", token: token)
        XCTAssertEqual(deleted.status, 204)
        let gone = await call(server, "GET", "/jobs/\(first.jobId)", token: token)
        XCTAssertEqual(gone.status, 404)
        shared.released = true
    }

    func testStatusCodesForEveryError() {
        for code in APIErrorCode.allCases {
            let status = BackendServer.status(for: code.rawValue)
            XCTAssertTrue((400..<600).contains(status), "\(code) → \(status)")
        }
        XCTAssertEqual(BackendServer.status(for: "что-то новое"), 500)
    }

    func testDispositionKeepsCyrillicName() {
        let value = BackendServer.disposition("Лекция \"1\".mp4")
        XCTAssertTrue(value.hasPrefix("attachment; filename=\""))
        XCTAssertFalse(value.dropFirst("attachment; filename=\"".count).prefix(12).contains("\""),
                       "кавычки из названия не ломают заголовок")
        XCTAssertTrue(value.contains("filename*=UTF-8''%D0%9B%D0%B5%D0%BA"))
    }
}
