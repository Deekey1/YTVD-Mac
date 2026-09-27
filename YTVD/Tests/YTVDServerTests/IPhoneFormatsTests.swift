import XCTest
@testable import YTVDCore

/// Нормализация форматов под iPhone. Образец — настоящий ответ YouTube по 4K-ролику:
/// у 1080p60 и 720p60 есть H.264, а 1440p60 и 2160p60 существуют только в VP9 и AV1.
final class IPhoneFormatsTests: XCTestCase {

    private func fixture(_ name: String) throws -> MediaInfo {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json",
                                                  subdirectory: "Fixtures"))
        return try JSONDecoder().decode(MediaInfo.self, from: Data(contentsOf: url))
    }

    func testRealYouTubeResponseGivesCleanLadder() throws {
        let choices = IPhoneFormats.build(from: try fixture("youtube-4k"), canMerge: true, canTranscode: true)
        let labels = choices.map(\.format.label)
        XCTAssertEqual(labels, ["2160p60", "1440p60", "1080p60", "720p60", "480p", "360p", "Только звук"],
                       "одна строка на разрешение, по убыванию, без внутренних номеров yt-dlp")
    }

    func testH264UpTo1080IsCopiedNotTranscoded() throws {
        let choices = IPhoneFormats.build(from: try fixture("youtube-4k"), canMerge: true, canTranscode: true)
        for height in [1080, 720] {
            let choice = try XCTUnwrap(choices.first { $0.format.height == height })
            XCTAssertFalse(choice.format.needsTranscode, "\(height)p есть в H.264 — перекодировать незачем")
            XCTAssertNil(choice.transcode)
            XCTAssertEqual(choice.format.codec, "h264")
            XCTAssertTrue(choice.plan.selector.hasPrefix("299+") || choice.plan.selector.hasPrefix("298+"),
                          "ожидали H.264-дорожку YouTube, получили \(choice.plan.selector)")
        }
    }

    /// AVPlayer не играет VP9, а AV1 — только на новых iPhone. Выше 1080p YouTube даёт только их.
    func testAbove1080IsTranscodedToHEVC() throws {
        let choices = IPhoneFormats.build(from: try fixture("youtube-4k"), canMerge: true, canTranscode: true)
        for height in [2160, 1440] {
            let choice = try XCTUnwrap(choices.first { $0.format.height == height })
            XCTAssertTrue(choice.format.needsTranscode)
            XCTAssertEqual(choice.format.codec, "hevc")
            XCTAssertEqual(choice.transcode?.encoder, "hevc_videotoolbox")
            XCTAssertEqual(choice.plan.container, "mkv", "промежуточный файл — mkv, итог — mp4")
            XCTAssertEqual(choice.finalExtension, "mp4")
            XCTAssertTrue(choice.format.sizeIsEstimated)
        }
    }

    func testWithoutTranscodingHighResolutionsDisappear() throws {
        let choices = IPhoneFormats.build(from: try fixture("youtube-4k"), canMerge: true, canTranscode: false)
        XCTAssertFalse(choices.contains { ($0.format.height ?? 0) > 1080 },
                       "нечем перекодировать — не обещаем то, что iPhone не проиграет")
    }

    func testPublicIdsAreStableAndNotYtDlpIds() throws {
        let choices = IPhoneFormats.build(from: try fixture("youtube-4k"), canMerge: true, canTranscode: true)
        XCTAssertEqual(choices.map(\.format.id),
                       ["h2160-60", "h1440-60", "h1080-60", "h720-60", "h480", "h360", "audio"])
    }

    func testRecommendedIsFullHDWithoutTranscoding() throws {
        let choices = IPhoneFormats.build(from: try fixture("youtube-4k"), canMerge: true, canTranscode: true)
        XCTAssertEqual(IPhoneFormats.recommended(choices), "h1080-60")
        XCTAssertEqual(IPhoneFormats.recommended(choices, preferredHeight: 720), "h720-60")
    }

    func testAudioOptionUsesStereoAAC() throws {
        let choices = IPhoneFormats.build(from: try fixture("youtube-4k"), canMerge: true, canTranscode: true)
        let audio = try XCTUnwrap(choices.first { $0.format.id == "audio" })
        XCTAssertFalse(audio.format.hasVideo)
        XCTAssertEqual(audio.format.codec, "aac")
        XCTAssertEqual(audio.finalExtension, "m4a")
    }

    /// Вертикальное видео 1080×1920 — это 1080p, а не «1920p».
    func testVerticalVideoIsClassifiedByShortSide() {
        let vertical = RawFormat(format_id: "v", ext: "mp4", vcodec: "avc1", acodec: "none",
                                 height: 1920, width: 1080)
        XCTAssertEqual(IPhoneFormats.resolutionClass(vertical), 1080)
    }

    func testOddResolutionsSnapToStandard() {
        XCTAssertEqual(IPhoneFormats.snap(1072), 1080)
        XCTAssertEqual(IPhoneFormats.snap(800), 720)
        XCTAssertEqual(IPhoneFormats.snap(2160), 2160)
        XCTAssertNil(IPhoneFormats.snap(100))
    }

    /// Rutube и VK отдают готовые файлы со звуком — склейка не нужна.
    func testCombinedFormatsWorkWithoutFfmpeg() {
        let info = MediaInfo(id: "r", title: "Ролик", duration: 120, formats: [
            RawFormat(format_id: "m3u8-720", ext: "mp4", vcodec: "avc1.64001f", acodec: "mp4a.40.2",
                      height: 720, width: 1280, tbr: 2000),
            RawFormat(format_id: "m3u8-360", ext: "mp4", vcodec: "avc1.42c01e", acodec: "mp4a.40.2",
                      height: 360, width: 640, tbr: 700),
        ])
        let choices = IPhoneFormats.build(from: info, canMerge: false, canTranscode: false)
        XCTAssertEqual(choices.filter(\.format.hasVideo).map(\.format.label), ["720p", "360p"])
        XCTAssertTrue(choices.allSatisfy { !$0.format.needsTranscode })
    }

    func testHDRIsSkipped() {
        let info = MediaInfo(id: "h", title: "HDR", duration: 60, formats: [
            RawFormat(format_id: "hdr", ext: "mp4", vcodec: "avc1", acodec: "none", height: 1080,
                      tbr: 9000, dynamic_range: "HDR10"),
            RawFormat(format_id: "140", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2", abr: 128),
        ])
        let choices = IPhoneFormats.build(from: info, canMerge: true, canTranscode: true)
        XCTAssertFalse(choices.contains { $0.format.height == 1080 }, "HDR на iPhone без тонмаппинга выглядит плохо")
    }

    func testThumbnailCandidatesKeepFallbacks() throws {
        let info = try fixture("youtube-4k")
        let list = info.thumbnailCandidates
        XCTAssertGreaterThan(list.count, 3, "нужен запас на случай 404 у лучшей обложки")
        XCTAssertEqual(Set(list).count, list.count, "без повторов")
        XCTAssertFalse(list.first?.hasSuffix(".webp") ?? true, "JPEG раньше WebP того же качества")
    }
}
