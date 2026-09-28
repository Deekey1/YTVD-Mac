import XCTest
@testable import VideoDownloader

/// Адреса Mac: дом и Tailscale, порядок опроса, подписи маршрута.
final class ConnectionTests: XCTestCase {

    private let home = URL(string: "http://192.168.31.50:8765")!
    private let tailnet = URL(string: "http://macbook-pro.tail104177.ts.net:8765")!
    private let tailnetIP = URL(string: "http://100.118.111.42:8765")!

    func testCurrentAddressFirstWithoutDuplicates() {
        XCTAssertEqual(Connection.candidates(current: home, alternates: [home, tailnet]), [home, tailnet])
        XCTAssertEqual(Connection.candidates(current: tailnet, alternates: [home, tailnet]), [tailnet, home],
                       "вне дома начинаем с того адреса, что работал в прошлый раз")
        XCTAssertEqual(Connection.candidates(current: home, alternates: []), [home])
    }

    func testRawTailnetAddressesAreSkipped() {
        // Обычный HTTP на 100.x iOS не пускает — такой адрес только зря ждал бы ответа.
        XCTAssertEqual(Connection.candidates(current: home, alternates: [home, tailnet, tailnetIP]), [home, tailnet])
    }

    func testTailnetRange() {
        XCTAssertTrue(Connection.isTailnet("100.118.111.42"))
        XCTAssertTrue(Connection.isTailnet("100.64.0.1"))
        XCTAssertFalse(Connection.isTailnet("100.63.0.1"))
        XCTAssertFalse(Connection.isTailnet("100.128.0.1"))
        XCTAssertFalse(Connection.isTailnet("192.168.31.50"))
    }

    @MainActor
    func testRouteTitles() {
        XCTAssertEqual(Connection.route(for: tailnet), "через Tailscale")
        XCTAssertEqual(Connection.route(for: tailnetIP), "через Tailscale")
        XCTAssertEqual(Connection.route(for: home), "в домашней сети")
        XCTAssertEqual(Connection.route(for: URL(string: "http://10.0.0.5:8765")), "в домашней сети")
        XCTAssertEqual(Connection.route(for: URL(string: "http://macbook.local:8765")), "в домашней сети")
        XCTAssertNil(Connection.route(for: URL(string: "http://example.com:8765")))
        XCTAssertNil(Connection.route(for: nil))
    }

    /// Из «Поделиться» ссылка приходит дважды — вторая копия не должна запускать новый разбор.
    @MainActor
    func testSameLinkFromShareIsRecognized() {
        XCTAssertTrue(DownloadModel.sameLink("https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                                             "https://www.youtube.com/watch?v=aqz-KE-bpKQ"))
        XCTAssertTrue(DownloadModel.sameLink("Big Buck Bunny https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                                             "https://www.youtube.com/watch?v=aqz-KE-bpKQ"))
        XCTAssertFalse(DownloadModel.sameLink("https://www.youtube.com/watch?v=aqz-KE-bpKQ",
                                              "https://www.youtube.com/watch?v=jNQXAC9IVRw"))
        XCTAssertFalse(DownloadModel.sameLink("https://www.youtube.com/watch?v=aqz-KE-bpKQ", ""))
    }
}
