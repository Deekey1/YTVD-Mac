import XCTest
import YTVDAPI
@testable import VideoDownloader

/// Варианты качества в интерфейсе и выбор по умолчанию.
final class FormatTests: XCTestCase {

    private var formats: [VideoFormat] {
        (try? API.decoder.decode(VideoInfo.self, from: Data(APIDecodingTests.resolveJSON.utf8)).formats) ?? []
    }

    private func format(_ label: String, height: Int?, fps: Int? = nil, size: Int64? = nil,
                        estimated: Bool = false, video: Bool = true) -> VideoFormat {
        VideoFormat(id: label, label: label, height: height, fps: fps, codec: video ? "h264" : "aac",
                    container: "mp4", hasVideo: video, hasAudio: true, estimatedSize: size,
                    sizeIsEstimated: estimated, needsTranscode: false)
    }

    func testTitlesAndSizes() {
        XCTAssertEqual(format("2160p60", height: 2160, fps: 60).displayTitle, "4K · 2160p60")
        XCTAssertEqual(format("1440p", height: 1440).displayTitle, "1440p")
        XCTAssertEqual(format("Только звук", height: nil, video: false).displayTitle, "Только звук")

        XCTAssertEqual(format("1080p", height: 1080, size: 483_000_000).sizeText, "483 МБ")
        XCTAssertEqual(format("2160p", height: 2160, size: 1_800_000_000, estimated: true).sizeText, "~1,8 ГБ",
                       "прикинутый по битрейту размер помечен как примерный")
        XCTAssertNil(format("720p", height: 720).sizeText)
    }

    func testVerticalVideoIsClassifiedByLabel() {
        // У вертикального ролика «1080p» — короткая сторона, даже если высота кадра 1920.
        XCTAssertEqual(format("1080p", height: 1920).classHeight, 1080)
    }

    func testDefaultQualityPick() {
        let list = formats
        XCTAssertEqual(DefaultQuality.p1080.pick(from: list)?.id, "h1080-60")
        XCTAssertEqual(DefaultQuality.p1440.pick(from: list)?.id, "h1080-60", "1440p нет — берём ближайшее снизу")
        XCTAssertEqual(DefaultQuality.best.pick(from: list)?.id, "h2160-60")
        XCTAssertEqual(DefaultQuality.p720.pick(from: list)?.id, "h720-60")

        let onlyHigh = [format("2160p", height: 2160), format("1440p", height: 1440)]
        XCTAssertEqual(DefaultQuality.p720.pick(from: onlyHigh)?.label, "1440p", "всё выше потолка — самое скромное")

        let audio = [format("Только звук", height: nil, video: false)]
        XCTAssertEqual(DefaultQuality.p1080.pick(from: audio)?.label, "Только звук")
    }

    func testRussianNumbers() {
        XCTAssertEqual(Fmt.bytes(950_000), "950 КБ")
        XCTAssertEqual(Fmt.bytes(12_400_000), "12,4 МБ")
        XCTAssertEqual(Fmt.bytes(483_000_000), "483 МБ")
        XCTAssertEqual(Fmt.bytes(2_392_000_000), "2,4 ГБ")
        XCTAssertEqual(Fmt.duration(42), "0:42")
        XCTAssertEqual(Fmt.duration(754), "12:34")
        XCTAssertEqual(Fmt.duration(3723), "1:02:03")
        XCTAssertEqual(Fmt.eta(11), "~11 с")
        XCTAssertEqual(Fmt.eta(200), "~4 мин")
        XCTAssertEqual(Fmt.eta(3900), "~1 ч 5 мин")
        XCTAssertEqual(Fmt.percent(0.745), "74 %")
    }
}
