import XCTest
import YTVDAPI
@testable import VideoDownloader

/// Ссылки: что приходит из «Поделиться» и буфера обмена, и адрес Mac, введённый руками.
final class LinkAndAddressTests: XCTestCase {

    func testYouTubeShareTextGivesVideoLink() {
        // Так делится приложение YouTube: название, потом короткая ссылка с меткой si.
        let shared = "Big Buck Bunny 60fps 4K https://youtu.be/aqz-KE-bpKQ?si=Xq2mKc0aB1"
        let url = LinkDetector.firstSupportedURL(in: shared)
        XCTAssertEqual(url?.host(), "youtu.be")
        XCTAssertTrue(url?.absoluteString.contains("aqz-KE-bpKQ") == true)
    }

    func testSupportedPlatforms() {
        let links = [
            "https://www.youtube.com/watch?v=aqz-KE-bpKQ",
            "https://m.youtube.com/watch?v=aqz-KE-bpKQ",
            "https://youtube.com/shorts/abcdefghijk",
            "https://vimeo.com/76979871",
            "https://rutube.ru/video/0123456789abcdef0123456789abcdef/",
            "https://vkvideo.ru/video-123_456",
        ]
        for link in links {
            XCTAssertNotNil(LinkDetector.firstSupportedURL(in: link), link)
        }
    }

    func testNotALink() {
        XCTAssertNil(LinkDetector.firstSupportedURL(in: "привет"))
        XCTAssertNil(LinkDetector.firstSupportedURL(in: ""))
        XCTAssertNil(LinkDetector.firstSupportedURL(in: "https://example.com/video"))
    }

    func testShareExtensionFallsBackToAnyWebLink() {
        XCTAssertEqual(SharedInbox.firstWebURL(in: "смотри https://example.com/a?b=1 тут")?.host(), "example.com")
        XCTAssertNil(SharedInbox.firstWebURL(in: "без ссылок"))
    }

    func testDeepLinkRoundTrip() throws {
        let original = try XCTUnwrap(URL(string: "https://youtu.be/aqz-KE-bpKQ?si=a&t=10"))
        let deepLink = try XCTUnwrap(SharedInbox.deepLink(for: original))
        XCTAssertEqual(deepLink.scheme, "videodownloader")
        XCTAssertEqual(SharedInbox.link(fromDeepLink: deepLink), original, "параметры ссылки не теряются")
        XCTAssertNil(SharedInbox.link(fromDeepLink: URL(string: "https://youtu.be/x")!))
    }

    func testManualServerAddress() {
        XCTAssertEqual(APIClient.normalize("192.168.1.10")?.absoluteString, "http://192.168.1.10:8765")
        XCTAssertEqual(APIClient.normalize(" 192.168.1.10:9000 ")?.absoluteString, "http://192.168.1.10:9000")
        XCTAssertEqual(APIClient.normalize("http://macbook.local:8765/api/v1/info")?.absoluteString,
                       "http://macbook.local:8765", "путь отрезается — клиент добавит свой")
        XCTAssertNil(APIClient.normalize(""))
        XCTAssertNil(APIClient.normalize("ftp://192.168.1.10"))
    }
}
