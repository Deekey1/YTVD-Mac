import XCTest
@testable import YTVDCore

final class LinkTests: XCTestCase {

    func testDetectsAllSupportedPlatforms() {
        let cases: [(String, MediaSource)] = [
            ("https://www.youtube.com/watch?v=aqz-KE-bpKQ", .youtube),
            ("https://youtu.be/aqz-KE-bpKQ", .youtube),
            ("https://m.youtube.com/watch?v=x", .youtube),
            ("https://music.youtube.com/watch?v=x", .youtube),
            ("https://vimeo.com/76979871", .vimeo),
            ("https://player.vimeo.com/video/76979871", .vimeo),
            ("https://rutube.ru/video/abc123/", .rutube),
            ("https://vk.com/video-1_2", .vk),
            ("https://vkvideo.ru/video-1_2", .vk),
            ("https://example.com/video", .other),
        ]
        for (raw, expected) in cases {
            let url = URL(string: raw)!
            XCTAssertEqual(MediaSource.detect(url), expected, "не распознан \(raw)")
        }
    }

    func testHostSuffixMatchingDoesNotMisfire() {
        // notyoutube.com не должен считаться YouTube.
        XCTAssertEqual(MediaSource.detect(URL(string: "https://notyoutube.com/watch?v=1")!), .other)
        XCTAssertEqual(MediaSource.detect(URL(string: "https://youtube.com.evil.ru/x")!), .other)
    }

    func testFirstSupportedURLInMessyText() {
        let text = "Смотри вот это (https://youtu.be/aqz-KE-bpKQ). Круто!"
        XCTAssertEqual(LinkDetector.firstSupportedURL(in: text)?.absoluteString,
                       "https://youtu.be/aqz-KE-bpKQ")
    }

    func testAddsSchemeWhenMissing() {
        XCTAssertEqual(LinkDetector.firstSupportedURL(in: "youtu.be/abc")?.absoluteString,
                       "https://youtu.be/abc")
    }

    func testIgnoresUnsupportedAndGarbage() {
        XCTAssertNil(LinkDetector.firstSupportedURL(in: "просто текст"))
        XCTAssertNil(LinkDetector.firstSupportedURL(in: "https://example.com/a"))
        XCTAssertNil(LinkDetector.firstSupportedURL(in: ""))
        XCTAssertNil(LinkDetector.firstSupportedURL(in: "file:///etc/passwd"))
    }

    func testPicksFirstSupportedAmongSeveral() {
        let text = "https://example.com/x https://vimeo.com/76979871 https://youtu.be/z"
        XCTAssertEqual(LinkDetector.firstSupportedURL(in: text)?.host, "vimeo.com")
    }

    func testNormalizeRejectsNonHTTP() {
        XCTAssertNil(LinkDetector.normalize("ftp://vk.com/video1"))
        XCTAssertNil(LinkDetector.normalize("/Users/me/file.mp4"))
        XCTAssertNotNil(LinkDetector.normalize("http://rutube.ru/video/1/"))
    }
}
