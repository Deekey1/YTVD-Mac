import XCTest
@testable import YTVDCore

final class HTTPParserTests: XCTestCase {

    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testCompleteRequestWithBody() throws {
        let raw = "POST /api/v1/resolve?x=1 HTTP/1.1\r\nHost: mac\r\nContent-Length: 11\r\n"
            + "Authorization: Bearer abc\r\n\r\n{\"url\":\"u\"}"
        XCTAssertEqual(HTTPParser.check(data(raw)), .complete(consumed: data(raw).count))
        let request = try XCTUnwrap(HTTPParser.parse(data(raw)))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/api/v1/resolve")
        XCTAssertEqual(request.query["x"], "1")
        XCTAssertEqual(request.header("AUTHORIZATION"), "Bearer abc", "имена заголовков без учёта регистра")
        XCTAssertEqual(String(decoding: request.body, as: UTF8.self), "{\"url\":\"u\"}")
    }

    func testWaitsForMissingHeadersAndBody() {
        XCTAssertEqual(HTTPParser.check(data("GET /a HTTP/1.1\r\nHost: m")), .needMore)
        let partialBody = "POST /a HTTP/1.1\r\nContent-Length: 10\r\n\r\n12345"
        XCTAssertEqual(HTTPParser.check(data(partialBody)), .needMore, "тело пришло не целиком")
    }

    func testRejectsOversizedAndMalformed() {
        let huge = "GET /a HTTP/1.1\r\nX: " + String(repeating: "a", count: 40_000) + "\r\n\r\n"
        XCTAssertEqual(HTTPParser.check(data(huge)), .invalid(status: 431))
        XCTAssertEqual(HTTPParser.check(data("POST /a HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n")),
                       .invalid(status: 413))
        XCTAssertEqual(HTTPParser.check(data("POST /a HTTP/1.1\r\nContent-Length: abc\r\n\r\n")),
                       .invalid(status: 400))
        XCTAssertNil(HTTPParser.parse(data("NONSENSE\r\n\r\n")))
    }

    func testPercentEncodedPathIsDecoded() throws {
        let request = try XCTUnwrap(HTTPParser.parse(data("GET /api/v1/jobs/a%20b HTTP/1.1\r\n\r\n")))
        XCTAssertEqual(request.path, "/api/v1/jobs/a b")
    }

    func testResponseHeadCarriesLengthAndClose() {
        let response = HTTPResponse.json(["a": 1])
        let head = String(decoding: response.head(), as: UTF8.self)
        XCTAssertTrue(head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(head.contains("Content-Length: \(response.contentLength)"))
        XCTAssertTrue(head.contains("Connection: close"))
        XCTAssertTrue(head.hasSuffix("\r\n\r\n"))
    }
}

final class ByteRangeTests: XCTestCase {

    func testAllRangeForms() {
        XCTAssertEqual(ByteRange.parse("bytes=0-99", size: 1000), .partial(offset: 0, length: 100))
        XCTAssertEqual(ByteRange.parse("bytes=500-", size: 1000), .partial(offset: 500, length: 500))
        XCTAssertEqual(ByteRange.parse("bytes=-100", size: 1000), .partial(offset: 900, length: 100))
        XCTAssertEqual(ByteRange.parse("bytes=900-5000", size: 1000), .partial(offset: 900, length: 100),
                       "конец за пределами файла прижимается к последнему байту")
    }

    func testInvalidRanges() {
        XCTAssertEqual(ByteRange.parse("bytes=1000-", size: 1000), .unsatisfiable)
        XCTAssertEqual(ByteRange.parse("bytes=50-10", size: 1000), .unsatisfiable)
        XCTAssertEqual(ByteRange.parse("bytes=-0", size: 1000), .unsatisfiable)
    }

    func testIgnoredRangesMeanFullFile() {
        XCTAssertEqual(ByteRange.parse(nil, size: 1000), .full)
        XCTAssertEqual(ByteRange.parse("items=0-1", size: 1000), .full)
        XCTAssertEqual(ByteRange.parse("bytes=0-1,5-9", size: 1000), .full, "несколько диапазонов — отдаём целиком")
    }
}

final class PairingTests: XCTestCase {

    func testCodeExchangesForTokenOnce() {
        let pairing = PairingManager(directory: Fixtures.temporaryDirectory())
        let (code, _) = pairing.newCode()
        XCTAssertEqual(code.count, 6)
        XCTAssertEqual(pairing.pair(code: code), .success(token: pairing.token))
        XCTAssertEqual(pairing.pair(code: code), .expired, "код одноразовый")
    }

    func testCodeBurnsAfterFiveWrongAttempts() {
        let pairing = PairingManager(directory: Fixtures.temporaryDirectory())
        let (code, _) = pairing.newCode()
        let wrong = code == "000000" ? "111111" : "000000"
        for _ in 1..<PairingManager.maxAttempts {
            XCTAssertEqual(pairing.pair(code: wrong), .invalid)
        }
        XCTAssertEqual(pairing.pair(code: wrong), .expired, "пятая ошибка сжигает код")
        XCTAssertEqual(pairing.pair(code: code), .expired, "даже верный код после этого не проходит")
    }

    func testCodeExpires() {
        final class Clock: @unchecked Sendable { var now = Date() }
        let clock = Clock()
        let pairing = PairingManager(directory: Fixtures.temporaryDirectory(), now: { clock.now })
        let (code, _) = pairing.newCode(validFor: 300)
        clock.now = clock.now.addingTimeInterval(301)
        XCTAssertNil(pairing.activeCode)
        XCTAssertEqual(pairing.pair(code: code), .expired)
    }

    func testTokenPersistsAndCanBeRevoked() {
        let directory = Fixtures.temporaryDirectory()
        let first = PairingManager(directory: directory).token
        XCTAssertGreaterThanOrEqual(first.count, 40)
        XCTAssertEqual(PairingManager(directory: directory).token, first, "токен переживает перезапуск")

        let pairing = PairingManager(directory: directory)
        pairing.revokeAll()
        XCTAssertNotEqual(pairing.token, first)

        let permissions = try? FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("token").path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600, "токен читает только владелец")
    }

    func testAuthorizationHeader() {
        let pairing = PairingManager(directory: Fixtures.temporaryDirectory())
        XCTAssertTrue(pairing.isAuthorized("Bearer \(pairing.token)"))
        XCTAssertTrue(pairing.isAuthorized("bearer \(pairing.token)"))
        XCTAssertFalse(pairing.isAuthorized(pairing.token), "без слова Bearer не принимаем")
        XCTAssertFalse(pairing.isAuthorized("Bearer wrong"))
        XCTAssertFalse(pairing.isAuthorized(nil))
    }
}

final class AddressTests: XCTestCase {
    func testTailnetRange() {
        XCTAssertTrue(IPhoneServer.isTailnet("100.118.111.42"))
        XCTAssertTrue(IPhoneServer.isTailnet("100.64.0.1"))
        XCTAssertTrue(IPhoneServer.isTailnet("100.127.255.254"))
        XCTAssertFalse(IPhoneServer.isTailnet("100.63.255.255"))
        XCTAssertFalse(IPhoneServer.isTailnet("100.128.0.1"))
        XCTAssertFalse(IPhoneServer.isTailnet("192.168.31.50"))
        XCTAssertFalse(IPhoneServer.isTailnet("fd7a:115c:a1e0::1"))
    }

    func testTailnetNames() {
        XCTAssertTrue(IPhoneServer.isTailnetName("macbook-pro.tail104177.ts.net"))
        XCTAssertTrue(IPhoneServer.isTailnetName("MacBook-Pro.Tail1.TS.NET"))
        XCTAssertFalse(IPhoneServer.isTailnetName("macbook-pro.local"))
        XCTAssertFalse(IPhoneServer.isTailnetName("ts.net.example.com"))
        // На этом Mac имя, если оно есть, соответствует адресу Tailscale.
        XCTAssertTrue(IPhoneServer.tailnetNames().allSatisfy(IPhoneServer.isTailnetName))
    }

    func testAddressListsDoNotOverlap() {
        let local = Set(IPhoneServer.localAddresses())
        let tailnet = Set(IPhoneServer.tailnetAddresses())
        XCTAssertTrue(local.isDisjoint(with: tailnet))
        XCTAssertTrue(tailnet.allSatisfy(IPhoneServer.isTailnet))
    }
}
