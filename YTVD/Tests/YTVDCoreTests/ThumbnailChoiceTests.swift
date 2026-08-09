import XCTest
@testable import YTVDCore

/// Выбор обложки. У YouTube лучшие картинки приходят без размеров, зато с бо́льшим `preference`,
/// поэтому наивный выбор «по ширине» брал мелкую 640×480.
final class ThumbnailChoiceTests: XCTestCase {

    func testPrefersHigherPreferenceEvenWithoutDimensions() {
        let info = MediaInfo(thumbnails: [
            RawThumbnail(url: "https://i/default.jpg", width: 120, height: 90, preference: -37),
            RawThumbnail(url: "https://i/sddefault.jpg", width: 640, height: 480, preference: -20),
            RawThumbnail(url: "https://i/maxresdefault.jpg", preference: -1),
        ])
        XCTAssertEqual(info.bestThumbnail?.url, "https://i/maxresdefault.jpg")
    }

    func testPrefersJPEGOverWebPOfSameQuality() {
        let info = MediaInfo(thumbnails: [
            RawThumbnail(url: "https://i/hq720.jpg", preference: -3),
            RawThumbnail(url: "https://i/maxresdefault.jpg", preference: -1),
            RawThumbnail(url: "https://i/maxresdefault.webp", preference: 0),
        ])
        XCTAssertEqual(info.bestThumbnail?.url, "https://i/maxresdefault.jpg",
                       "JPEG не нужно перекодировать — берём его")
    }

    func testTakesWebPWhenNothingElseIsAvailable() {
        let info = MediaInfo(thumbnails: [
            RawThumbnail(url: "https://i/a.webp", preference: 0),
            RawThumbnail(url: "https://i/b.webp", preference: -5),
        ])
        XCTAssertEqual(info.bestThumbnail?.url, "https://i/a.webp")
    }

    func testFallsBackToWidthWhenPreferenceIsAbsent() {
        let info = MediaInfo(thumbnails: [
            RawThumbnail(url: "https://i/small.jpg", width: 320, height: 180),
            RawThumbnail(url: "https://i/big.jpg", width: 1920, height: 1080),
        ])
        XCTAssertEqual(info.bestThumbnail?.url, "https://i/big.jpg")
    }

    func testFallsBackToSingleThumbnailField() {
        let info = MediaInfo(thumbnail: "https://i/only.jpg", thumbnails: [])
        XCTAssertEqual(info.bestThumbnail?.url, "https://i/only.jpg")
    }

    func testNoThumbnailsAtAll() {
        XCTAssertNil(MediaInfo(id: "x").bestThumbnail)
    }

    func testCoverOptionAppearsWhenOnlyPlainThumbnailIsKnown() {
        let info = MediaInfo(id: "x", title: "Ролик", duration: 60,
                             thumbnail: "https://i/only.jpg",
                             formats: [RawFormat(format_id: "18", ext: "mp4", vcodec: "avc1",
                                                 acodec: "mp4a.40.2", height: 360, tbr: 500)])
        let cover = OptionBuilder.build(from: info).first { $0.group == .cover }
        XCTAssertEqual(cover?.plan.coverURL, "https://i/only.jpg")
        XCTAssertEqual(cover?.subtitle, "исходный размер")
    }
}
