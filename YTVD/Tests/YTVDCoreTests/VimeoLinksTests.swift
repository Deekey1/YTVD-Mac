import XCTest
@testable import YTVDCore

/// Vimeo закрывает главную страницу от сторонних программ, но страница плеера открыта.
final class VimeoLinksTests: XCTestCase {

    private func player(_ raw: String) -> String? {
        VimeoLinks.playerURL(for: URL(string: raw)!)?.absoluteString
    }

    func testPlainVideoLink() {
        XCTAssertEqual(player("https://vimeo.com/1182843813"),
                       "https://player.vimeo.com/video/1182843813")
        XCTAssertEqual(player("https://www.vimeo.com/76979871"),
                       "https://player.vimeo.com/video/76979871")
    }

    func testUnlistedLinkKeepsAccessHash() {
        XCTAssertEqual(player("https://vimeo.com/1182843813/a1b2c3d4e5"),
                       "https://player.vimeo.com/video/1182843813?h=a1b2c3d4e5")
    }

    func testHashFromQueryIsCarriedOver() {
        XCTAssertEqual(player("https://vimeo.com/1182843813?h=deadbeef"),
                       "https://player.vimeo.com/video/1182843813?h=deadbeef")
    }

    func testPlayerLinkIsNotRewrittenTwice() {
        XCTAssertNil(player("https://player.vimeo.com/video/1182843813"))
    }

    func testNonNumericAndForeignLinksAreIgnored() {
        XCTAssertNil(player("https://vimeo.com/patrickclair"))
        XCTAssertNil(player("https://vimeo.com/channels/staffpicks"))
        XCTAssertNil(player("https://youtu.be/aqz-KE-bpKQ"))
    }

    func testCandidatesOrderPutsOriginalFirst() {
        let url = URL(string: "https://vimeo.com/76979871")!
        let list = VimeoLinks.candidates(for: url)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first, url)
        XCTAssertEqual(list.last?.host, "player.vimeo.com")
    }

    func testCandidatesForOtherPlatformsStaySingle() {
        let url = URL(string: "https://youtu.be/aqz-KE-bpKQ")!
        XCTAssertEqual(VimeoLinks.candidates(for: url), [url])
    }
}

final class VimeoErrorTests: XCTestCase {

    func testRestrictedEmbedIsExplainedPlainly() {
        let privacy = YtDlpOutput.humanError("PrivacyError: We're having a little trouble",
                                             source: .vimeo)
        XCTAssertTrue(privacy.contains("ограничил доступ"), "получили: \(privacy)")

        let unauthorized = YtDlpOutput.humanError(
            "Unable to download webpage: HTTP Error 401: Unauthorized", source: .vimeo)
        XCTAssertTrue(unauthorized.contains("ограничил доступ"), "получили: \(unauthorized)")
    }

    /// 401 при получении токена — это другое: там дело в доступе, а не в правах владельца.
    func testOAuthFailureStillAdvisesLogin() {
        let message = YtDlpOutput.humanError("Failed to fetch macos OAuth token: HTTP Error 401",
                                             source: .vimeo)
        XCTAssertTrue(message.contains("cookies"), "получили: \(message)")
    }
}
