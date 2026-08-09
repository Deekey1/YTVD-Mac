import XCTest
@testable import YTVDCore

final class OptionBuilderTests: XCTestCase {

    /// Набор форматов, похожий на настоящую выдачу YouTube.
    private func youtubeLike() -> MediaInfo {
        let audio = [
            RawFormat(format_id: "140", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2",
                      filesize: 10_100_000, tbr: 128, abr: 128),
            RawFormat(format_id: "251", ext: "webm", vcodec: "none", acodec: "opus",
                      filesize: 8_400_000, tbr: 112, abr: 112),
        ]
        let video = [
            RawFormat(format_id: "313", ext: "webm", vcodec: "vp09.00.50.08", acodec: "none",
                      height: 2160, fps: 30, filesize: 900_000_000, tbr: 18_000),
            RawFormat(format_id: "266", ext: "mp4", vcodec: "avc1.640033", acodec: "none",
                      height: 2160, fps: 30, filesize: 1_400_000_000, tbr: 22_000),
            RawFormat(format_id: "137", ext: "mp4", vcodec: "avc1.640028", acodec: "none",
                      height: 1080, fps: 30, filesize: 320_000_000, tbr: 4_100),
            RawFormat(format_id: "248", ext: "webm", vcodec: "vp09.00.40.08", acodec: "none",
                      height: 1080, fps: 30, filesize: 200_000_000, tbr: 2_600),
            RawFormat(format_id: "136", ext: "mp4", vcodec: "avc1.4d401f", acodec: "none",
                      height: 720, fps: 30, filesize: 160_000_000, tbr: 2_100),
            // Тот же 720p, но хуже — не должен победить.
            RawFormat(format_id: "136-lq", ext: "mp4", vcodec: "avc1.4d401f", acodec: "none",
                      height: 720, fps: 30, filesize: 90_000_000, tbr: 1_200),
        ]
        return MediaInfo(id: "abc", title: "Ролик", uploader: "Канал", duration: 632,
                         thumbnails: [RawThumbnail(url: "https://i.ytimg.com/hq.jpg", width: 1280, height: 720)],
                         formats: audio + video)
    }

    func testBuildsVideoAudioAndCoverGroups() {
        let options = OptionBuilder.build(from: youtubeLike())
        XCTAssertFalse(options.filter { $0.group == .video }.isEmpty)
        XCTAssertFalse(options.filter { $0.group == .audio }.isEmpty)
        XCTAssertEqual(options.filter { $0.group == .cover }.count, 1)
    }

    func testH264OptionsAreSortedFromHighToLowAndIncludeAudioSize() {
        let options = OptionBuilder.build(from: youtubeLike())
            .filter { $0.group == .video && !$0.isAlternative }
        XCTAssertEqual(options.map(\.height), [2160, 1080, 720])
        // 320 МБ видео + 10,1 МБ звука
        let fullHD = options.first { $0.height == 1080 }!
        XCTAssertEqual(fullHD.bytes, 320_000_000 + 10_100_000)
        XCTAssertFalse(fullHD.estimated)
    }

    func testPicksBestFormatPerHeight() {
        let options = OptionBuilder.build(from: youtubeLike())
        let hd = options.first { $0.height == 720 && !$0.isAlternative }!
        XCTAssertTrue(hd.plan.selector.hasPrefix("136+"), "ожидали лучший 720p, получили \(hd.plan.selector)")
    }

    func testSelectorPairsVideoWithAACAudio() {
        let options = OptionBuilder.build(from: youtubeLike())
        let fullHD = options.first { $0.height == 1080 && !$0.isAlternative }!
        XCTAssertEqual(fullHD.plan.selector, "137+140")
        XCTAssertEqual(fullHD.plan.container, "mp4")
        XCTAssertEqual(fullHD.plan.mode, .video)
    }

    func testTelegramBadgeOnlyForCompatibleHeights() {
        let options = OptionBuilder.build(from: youtubeLike())
        XCTAssertEqual(options.first { $0.height == 1080 && !$0.isAlternative }?.badge, "TG")
        XCTAssertEqual(options.first { $0.height == 720 && !$0.isAlternative }?.badge, "TG")
        XCTAssertNil(options.first { $0.height == 2160 && !$0.isAlternative }?.badge)
    }

    func testAlternativeCodecShownOnlyWhenNoticeablySmaller() {
        let options = OptionBuilder.build(from: youtubeLike())
        let alternatives = options.filter(\.isAlternative)
        // 1080p VP9 (200 МБ против 320 МБ) — проходит; 2160p VP9 (900 против 1400) — тоже.
        XCTAssertEqual(Set(alternatives.compactMap(\.height)), [1080, 2160])
        XCTAssertTrue(alternatives.allSatisfy { $0.tint == .orange })
    }

    func testAlternativeIsHiddenWhenSavingIsTiny() {
        var info = youtubeLike()
        // Делаем VP9 почти таким же по весу, как H.264.
        info.formats = info.formats!.map { format in
            var copy = format
            if copy.format_id == "248" { copy.filesize = 310_000_000 }
            return copy
        }
        let alternatives = OptionBuilder.build(from: info).filter(\.isAlternative)
        XCTAssertFalse(alternatives.contains { $0.height == 1080 })
    }

    func testAudioOptions() {
        let options = OptionBuilder.build(from: youtubeLike()).filter { $0.group == .audio }
        let mp3 = options.first { $0.plan.mode == .audioMP3 }
        XCTAssertNotNil(mp3)
        XCTAssertEqual(mp3?.title, "MP3")
        XCTAssertTrue(mp3!.estimated)
        // 320 кбит/с × 632 с ≈ 25,3 МБ
        XCTAssertEqual(Double(mp3!.bytes), 320 * 1000 / 8 * 632, accuracy: 1)

        let native = options.first { $0.plan.mode == .audioNative }
        XCTAssertEqual(native?.plan.selector, "140")   // лучший по битрейту — AAC 128
        XCTAssertEqual(native?.subtitle, "оригинал")
    }

    func testCoverOptionCarriesURL() {
        let cover = OptionBuilder.build(from: youtubeLike()).first { $0.group == .cover }
        XCTAssertEqual(cover?.plan.coverURL, "https://i.ytimg.com/hq.jpg")
        XCTAssertEqual(cover?.subtitle, "1280×720")
        XCTAssertEqual(cover?.plan.container, "jpg")
    }

    func testFallsBackToCombinedFormatsWhenNoSeparateTracks() {
        // Так отдают Rutube и VK: готовые файлы со звуком.
        let info = MediaInfo(id: "r1", title: "Ролик", duration: 300, formats: [
            RawFormat(format_id: "hls-720", ext: "mp4", vcodec: "avc1.4d401f", acodec: "mp4a.40.2",
                      height: 720, tbr: 2_000),
            RawFormat(format_id: "hls-480", ext: "mp4", vcodec: "avc1.4d401e", acodec: "mp4a.40.2",
                      height: 480, tbr: 1_000),
        ])
        let options = OptionBuilder.build(from: info).filter { $0.group == .video }
        XCTAssertEqual(options.map(\.height), [720, 480])
        XCTAssertEqual(options.first?.plan.selector, "hls-720", "склеенный формат берём как есть")
        XCTAssertTrue(options.allSatisfy(\.estimated), "размер считаем по битрейту")
    }

    /// YouTube отдаёт 5.1-дорожку с самым высоким битрейтом — для видео нужна стереофоническая.
    func testPrefersStereoAudioOverSurround() {
        let info = MediaInfo(id: "x", title: "Ролик", duration: 600, formats: [
            RawFormat(format_id: "258", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2",
                      filesize: 30_767_611, tbr: 388, abr: 388, audio_channels: 6),
            RawFormat(format_id: "140", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2",
                      filesize: 10_271_496, tbr: 129, abr: 129, audio_channels: 2),
            RawFormat(format_id: "137", ext: "mp4", vcodec: "avc1.640028", acodec: "none",
                      height: 1080, filesize: 300_000_000, tbr: 4_000),
        ])
        let options = OptionBuilder.build(from: info)

        let video = options.first { $0.group == .video }!
        XCTAssertEqual(video.plan.selector, "137+140", "к видео должна цепляться стереодорожка")
        XCTAssertEqual(video.bytes, 300_000_000 + 10_271_496)

        let native = options.first { $0.plan.mode == .audioNative }
        XCTAssertEqual(native?.plan.selector, "140")
    }

    func testFallsBackToSurroundWhenNoStereoExists() {
        let info = MediaInfo(id: "x", title: "Ролик", duration: 600, formats: [
            RawFormat(format_id: "258", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2",
                      filesize: 30_000_000, tbr: 388, abr: 388, audio_channels: 6),
            RawFormat(format_id: "137", ext: "mp4", vcodec: "avc1", acodec: "none",
                      height: 1080, filesize: 300_000_000, tbr: 4_000),
        ])
        let video = OptionBuilder.build(from: info).first { $0.group == .video }
        XCTAssertEqual(video?.plan.selector, "137+258")
    }

    func testMP3UsesConcreteAudioTrack() {
        let info = MediaInfo(id: "x", title: "Ролик", duration: 600, formats: [
            RawFormat(format_id: "251", ext: "webm", vcodec: "none", acodec: "opus",
                      filesize: 10_000_000, tbr: 130, abr: 130, audio_channels: 2),
        ])
        let mp3 = OptionBuilder.build(from: info).first { $0.plan.mode == .audioMP3 }
        XCTAssertEqual(mp3?.plan.selector, "251", "перекодируем конкретную дорожку, а не «что попало»")
    }

    /// Vimeo отдаёт звук отдельными дорожками, у которых кодек не указан вовсе.
    /// Раньше их принимали за «без звука», и видео скачивалось немым.
    func testVimeoStyleAudioTracksAreFound() {
        let info = MediaInfo(id: "v", title: "Ролик", duration: 62, formats: [
            RawFormat(format_id: "hls-audio-low", ext: "mp4", vcodec: "none", acodec: nil),
            RawFormat(format_id: "hls-audio-high", ext: "mp4", vcodec: "none", acodec: nil),
            RawFormat(format_id: "hls-2644", ext: "mp4", vcodec: "avc1.64001F", acodec: "none",
                      height: 720, tbr: 2644),
            RawFormat(format_id: "hls-407", ext: "mp4", vcodec: "avc1.42C01E", acodec: "none",
                      height: 270, tbr: 407),
        ])

        let options = OptionBuilder.build(from: info)
        let video = options.first { $0.height == 720 }
        XCTAssertEqual(video?.plan.selector, "hls-2644+hls-audio-high",
                       "к видео должна прицепиться звуковая дорожка, иначе файл выйдет немым")

        let native = options.first { $0.plan.mode == .audioNative }
        XCTAssertEqual(native?.plan.selector, "hls-audio-high", "из двух дорожек берём «high»")
        XCTAssertEqual(native?.title, "M4A", "звук в контейнере mp4 показываем как M4A")
    }

    func testProgressiveFormatWithoutCodecInfoCountsAsCompleteFile() {
        // yt-dlp часто не заполняет кодеки у цельных http-файлов.
        let format = RawFormat(format_id: "http-720p", ext: "mp4", height: 720)
        XCTAssertTrue(format.hasVideo)
        XCTAssertTrue(format.hasAudio)
    }

    func testExplicitNoneIsRespected() {
        let videoOnly = RawFormat(format_id: "137", vcodec: "avc1", acodec: "none", height: 1080)
        XCTAssertTrue(videoOnly.hasVideo)
        XCTAssertFalse(videoOnly.hasAudio)

        let audioOnly = RawFormat(format_id: "140", vcodec: "none", acodec: "mp4a.40.2")
        XCTAssertFalse(audioOnly.hasVideo)
        XCTAssertTrue(audioOnly.hasAudio)
    }

    func testUnknownSizeIsShownAsDash() {
        let info = MediaInfo(id: "v", title: "Ролик", duration: nil, formats: [
            RawFormat(format_id: "a", ext: "mp4", vcodec: "none", acodec: nil),
        ])
        let native = OptionBuilder.build(from: info).first { $0.plan.mode == .audioNative }
        XCTAssertEqual(native?.sizeText, "—")
        XCTAssertFalse(native?.hasKnownSize ?? true)
    }

    func testEmptyFormatsProduceNoVideoOptions() {
        let info = MediaInfo(id: "x", title: "Пусто", duration: nil, formats: [])
        XCTAssertTrue(OptionBuilder.build(from: info).isEmpty)
    }

    func testSizeEstimateFromBitrateWhenFilesizeMissing() {
        let info = MediaInfo(id: "x", title: "Ролик", duration: 100, formats: [
            RawFormat(format_id: "1", ext: "mp4", vcodec: "avc1", acodec: "none", height: 720, tbr: 800),
            RawFormat(format_id: "2", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2", tbr: 128),
        ])
        let video = OptionBuilder.build(from: info).first { $0.group == .video }!
        XCTAssertTrue(video.estimated)
        XCTAssertEqual(Double(video.bytes), (800 + 128) * 1000 / 8 * 100, accuracy: 2)
    }
}
