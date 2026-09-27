import XCTest
@testable import YTVDCore

final class YtDlpOutputTests: XCTestCase {

    func testParsesProgressLine() {
        let line = "YTVD|1048576|10485760|524288.0|18"
        guard case .progress(let progress) = YtDlpOutput.classify(line) else {
            return XCTFail("строка прогресса не распознана")
        }
        XCTAssertEqual(progress.downloaded, 1_048_576)
        XCTAssertEqual(progress.total, 10_485_760)
        XCTAssertEqual(progress.speed, 524_288)
        XCTAssertEqual(progress.eta, 18)
        XCTAssertEqual(progress.fraction!, 0.1, accuracy: 0.0001)
    }

    func testProgressWithUnknownFields() {
        let line = "YTVD|2048|NA|None|NA"
        guard case .progress(let progress) = YtDlpOutput.classify(line) else {
            return XCTFail("строка прогресса не распознана")
        }
        XCTAssertEqual(progress.downloaded, 2048)
        XCTAssertNil(progress.total)
        XCTAssertNil(progress.speed)
        XCTAssertNil(progress.eta)
        XCTAssertNil(progress.fraction)
    }

    func testFractionIsClamped() {
        let progress = DownloadProgress(downloaded: 200, total: 100)
        XCTAssertEqual(progress.fraction, 1)
    }

    func testClassifiesLifecycleLines() {
        XCTAssertEqual(YtDlpOutput.classify("[download] Destination: /tmp/a.f137.mp4"),
                       .destination("/tmp/a.f137.mp4"))
        XCTAssertEqual(YtDlpOutput.classify("[Merger] Merging formats into \"/tmp/a.mp4\""),
                       .merging("/tmp/a.mp4"))
        XCTAssertEqual(YtDlpOutput.classify("[ExtractAudio] Destination: /tmp/a.mp3"), .extractingAudio)
        XCTAssertEqual(YtDlpOutput.classify("[EmbedThumbnail] mp3"), .embeddingThumbnail)
        XCTAssertEqual(YtDlpOutput.classify("[download] /tmp/a.mp4 has already been downloaded"),
                       .alreadyDownloaded("/tmp/a.mp4"))
    }

    func testClassifiesErrors() {
        guard case .failure(let message) = YtDlpOutput.classify("ERROR: Video unavailable") else {
            return XCTFail("ошибка не распознана")
        }
        XCTAssertEqual(message, "Video unavailable")
    }

    func testHumanErrorTranslatesCommonCases() {
        XCTAssertEqual(YtDlpOutput.humanError("ERROR: Video unavailable"), "Видео недоступно")
        XCTAssertEqual(YtDlpOutput.humanError("ERROR: [youtube] aaaaaaaaaaa: This video is unavailable"),
                       "Видео недоступно")
        XCTAssertEqual(YtDlpOutput.humanError("ERROR: [youtube] x: This video has been removed by the uploader"),
                       "Видео недоступно")
        XCTAssertEqual(YtDlpOutput.humanError("ERROR: Private video. Sign in if you've been granted access"),
                       "Это приватное видео")
        XCTAssertEqual(YtDlpOutput.humanError("ERROR: The uploader has not made this video available in your country"),
                       "Ролик заблокирован в вашем регионе")
        XCTAssertEqual(YtDlpOutput.humanError("ERROR: Unable to download webpage: timed out"),
                       "Нет связи с площадкой — проверьте интернет")
        XCTAssertEqual(YtDlpOutput.humanError("ERROR: Unsupported URL: https://example.com"),
                       "Эта ссылка не поддерживается")
        XCTAssertEqual(YtDlpOutput.humanError(""), "Не удалось получить данные")
    }

    /// Самая частая беда при включённом VPN: площадка отвергает адрес дата-центра.
    func testHumanErrorExplainsAddressBlock() {
        let vimeo = "ERROR: [vimeo] 1182843813: Got HTTP Error 403 when using impersonate target "
            + "\"chrome-131:macos-14\". If you are using a data center IP or VPN/proxy, your IP may be blocked"

        // Для неизвестной площадки виноват адрес — про него и говорим.
        let generic = YtDlpOutput.humanError(vimeo, source: .other)
        XCTAssertTrue(generic.contains("VPN"), "получили: \(generic)")
        XCTAssertFalse(generic.contains("403"), "техническая деталь не нужна пользователю")

        // Для Rutube и VK совет обратный — им нужен российский адрес.
        let rutube = YtDlpOutput.humanError(vimeo, source: .rutube)
        XCTAssertTrue(rutube.contains("российских"), "получили: \(rutube)")
        XCTAssertTrue(YtDlpOutput.humanError(vimeo, source: .vk).contains("российских"))
    }

    /// Vimeo отвергает адрес по-разному: 403, 401 на OAuth-токене, обрыв по таймауту.
    func testAllVimeoRejectionShapesAreRecognised() {
        let cases = [
            "Got HTTP Error 403 when using impersonate target \"chrome-131:macos-14\"",
            "Failed to fetch macos OAuth token: HTTP Error 401: Unauthorized",
            "The android client is unable to fetch new OAuth tokens",
            "Error reading response: Failed to perform, curl: (28) Operation too slow",
        ]
        for raw in cases {
            XCTAssertTrue(YtDlpOutput.isAddressRelated(raw), "не распознано: \(raw)")
            // Vimeo отказывает и без VPN, поэтому подсказка всегда ведёт ко входу.
            let message = YtDlpOutput.humanError(raw, source: .vimeo)
            XCTAssertTrue(message.contains("Vimeo") && message.contains("cookies"),
                          "невнятная подсказка: \(message)")
        }
    }

    /// Vimeo отказывает и без VPN — совет должен вести ко входу, а не только к туннелю.
    func testVimeoAdviceDependsOnCookieSetting() {
        let raw = "Got HTTP Error 403 when using impersonate target \"chrome-131:macos-14\""

        let withoutCookies = YtDlpOutput.humanError(raw, source: .vimeo, hasCookies: false)
        XCTAssertTrue(withoutCookies.contains("Брать cookies из браузера"),
                      "получили: \(withoutCookies)")

        let withCookies = YtDlpOutput.humanError(raw, source: .vimeo, hasCookies: true)
        XCTAssertTrue(withCookies.contains("действительно вошли"), "получили: \(withCookies)")
        XCTAssertFalse(withCookies.contains("включите"), "cookies уже включены: \(withCookies)")
    }

    func testVPNNoteAppearsOnlyWhenTunnelIsUp() {
        let raw = "Failed to fetch macos OAuth token: HTTP Error 401: Unauthorized"
        XCTAssertTrue(YtDlpOutput.humanError(raw, source: .vimeo, viaVPN: true)
            .contains("трафик идёт через VPN"))
        XCTAssertFalse(YtDlpOutput.humanError(raw, source: .vimeo, viaVPN: false)
            .contains("трафик идёт через VPN"))
    }

    func testLoginRequiredIsNotBlamedOnVPN() {
        let raw = "The web client only works when logged-in. Use --cookies-from-browser"
        let message = YtDlpOutput.humanError(raw, source: .vimeo, viaVPN: true)
        XCTAssertTrue(message.contains("cookies"), "получили: \(message)")
        XCTAssertFalse(message.contains("VPN"), "вход и адрес — разные беды: \(message)")
    }

    func testOrdinaryErrorsAreNotTreatedAsAddressProblems() {
        XCTAssertFalse(YtDlpOutput.isAddressRelated("Video unavailable"))
        XCTAssertFalse(YtDlpOutput.isAddressRelated("Requested format is not available"))
        XCTAssertFalse(YtDlpOutput.isAddressRelated(""))
    }

    /// Rutube отдаёт описание ролика, а видео раздаёт отдельный сервер — и уже он отказывает.
    func testRutubeCDNRefusalGetsCountryAdvice() {
        let raw = "unable to download video data: HTTPSConnection(host='river-ntv-mts-d469.rtbcdn.ru', "
            + "port=443): Failed to establish a new connection: [Errno 61] Connection refused"

        XCTAssertTrue(YtDlpOutput.isAddressRelated(raw))
        let message = YtDlpOutput.humanError(raw, source: .rutube)
        XCTAssertTrue(message.contains("Сервер раздачи"), "получили: \(message)")
        XCTAssertTrue(message.contains("российских"), "получили: \(message)")
        XCTAssertFalse(message.contains("rtbcdn"), "техническое имя хоста пользователю не нужно")
    }

    func testHumanErrorSuggestsCookiesForBotCheck() {
        let message = YtDlpOutput.humanError("ERROR: Sign in to confirm you’re not a bot",
                                             source: .youtube)
        XCTAssertTrue(message.contains("cookies"), "получили: \(message)")
    }

    func testHumanErrorKeepsUnknownMessageButTrimsNoise() {
        let raw = "ERROR: something odd happened; please report this issue on https://github.com/..."
        XCTAssertEqual(YtDlpOutput.humanError(raw), "something odd happened")
    }

    func testFirstErrorPrefersExplicitErrorLine() {
        let stderr = "WARNING: something\nERROR: Video unavailable\ntrailing noise"
        XCTAssertEqual(MediaService.firstError(in: stderr), "ERROR: Video unavailable")
    }
}

final class YtDlpArgumentsTests: XCTestCase {

    func testMetadataArguments() {
        let args = YtDlpArguments.metadata(url: "https://youtu.be/x")
        XCTAssertTrue(args.contains("-J"))
        XCTAssertTrue(args.contains("--no-playlist"))
        XCTAssertEqual(args.last, "https://youtu.be/x")
    }

    func testVideoDownloadArguments() {
        let plan = DownloadPlan(mode: .video, selector: "137+140", container: "mp4")
        let args = YtDlpArguments.download(plan: plan, url: "https://youtu.be/x",
                                           basePath: "/tmp/Ролик [1080p]",
                                           ffmpegDirectory: "/opt/homebrew/bin")

        XCTAssertEqual(value(after: "-f", in: args), "137+140")
        XCTAssertEqual(value(after: "-o", in: args), "/tmp/Ролик [1080p].%(ext)s")
        XCTAssertEqual(value(after: "--merge-output-format", in: args), "mp4")
        XCTAssertEqual(value(after: "--ffmpeg-location", in: args), "/opt/homebrew/bin")
        XCTAssertEqual(value(after: "--progress-template", in: args),
                       "download:" + YtDlpOutput.progressTemplate)
        XCTAssertTrue(args.contains("--newline"))
        XCTAssertEqual(args.last, "https://youtu.be/x")
    }

    func testMP3DownloadArguments() {
        let plan = DownloadPlan(mode: .audioMP3, selector: "bestaudio/best", container: "mp3")
        let args = YtDlpArguments.download(plan: plan, url: "u", basePath: "/tmp/a", ffmpegDirectory: nil)
        XCTAssertTrue(args.contains("-x"))
        XCTAssertEqual(value(after: "--audio-format", in: args), "mp3")
        XCTAssertEqual(value(after: "--audio-quality", in: args), "320K")
        XCTAssertTrue(args.contains("--embed-thumbnail"))
        XCTAssertFalse(args.contains("--ffmpeg-location"))
    }

    func testNativeAudioDoesNotTranscode() {
        let plan = DownloadPlan(mode: .audioNative, selector: "140", container: "m4a")
        let args = YtDlpArguments.download(plan: plan, url: "u", basePath: "/tmp/a", ffmpegDirectory: nil)
        XCTAssertFalse(args.contains("-x"))
        XCTAssertFalse(args.contains("--merge-output-format"))
        XCTAssertEqual(value(after: "-f", in: args), "140")
    }

    func testNetworkOptionsAreAppliedToBothCommands() {
        let network = NetworkOptions(cookiesFromBrowser: "chrome", proxy: "socks5://127.0.0.1:1080")

        let info = YtDlpArguments.metadata(url: "https://youtu.be/x", network: network)
        XCTAssertEqual(value(after: "--cookies-from-browser", in: info), "chrome")
        XCTAssertEqual(value(after: "--proxy", in: info), "socks5://127.0.0.1:1080")
        XCTAssertEqual(info.last, "https://youtu.be/x", "ссылка остаётся последней")

        let plan = DownloadPlan(mode: .video, selector: "137+140", container: "mp4")
        let download = YtDlpArguments.download(plan: plan, url: "https://youtu.be/x",
                                               basePath: "/tmp/a", ffmpegDirectory: nil,
                                               network: network)
        XCTAssertEqual(value(after: "--cookies-from-browser", in: download), "chrome")
        XCTAssertEqual(value(after: "--proxy", in: download), "socks5://127.0.0.1:1080")
    }

    func testEmptyNetworkOptionsAddNothing() {
        let empty = NetworkOptions(cookiesFromBrowser: "", proxy: "")
        XCTAssertTrue(empty.arguments.isEmpty)
        XCTAssertTrue(NetworkOptions.none.arguments.isEmpty)

        let args = YtDlpArguments.metadata(url: "u")
        XCTAssertFalse(args.contains("--proxy"))
        XCTAssertFalse(args.contains("--cookies-from-browser"))
    }

    func testCoverPlanProducesNoArguments() {
        let plan = DownloadPlan(mode: .cover, selector: "", container: "jpg",
                                coverURL: "https://i.ytimg.com/x.jpg")
        XCTAssertTrue(YtDlpArguments.download(plan: plan, url: "u", basePath: "/tmp/a",
                                              ffmpegDirectory: nil).isEmpty)
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

final class FileNamingTests: XCTestCase {

    func testTemplateSubstitution() {
        let name = FileNaming.build(template: "{title} [{quality}]", title: "Ролик",
                                    quality: "1080p", source: "YouTube", id: "abc")
        XCTAssertEqual(name, "Ролик [1080p]")
    }

    func testTemplateWithAllTokens() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = FileNaming.build(template: "{source} — {title} {quality} {id} {date}",
                                    title: "Ролик", quality: "720p", source: "Vimeo",
                                    id: "77", date: date)
        XCTAssertTrue(name.hasPrefix("Vimeo — Ролик 720p 77 2023-11-"), "получили: \(name)")
    }

    func testEmptyTokensDoNotLeaveBrackets() {
        let name = FileNaming.build(template: "{title} [{quality}]", title: "Обложка",
                                    quality: "", source: "YouTube", id: "x")
        XCTAssertEqual(name, "Обложка")
    }

    func testUniqueBaseAvoidsCollisions() {
        let directory = URL(fileURLWithPath: "/tmp/ytvd-test")
        let taken: Set<String> = ["/tmp/ytvd-test/Ролик.mp4", "/tmp/ytvd-test/Ролик (2).mp4"]
        let name = FileNaming.uniqueBase(directory: directory, base: "Ролик",
                                         extensions: ["mp4", "mp3"],
                                         exists: { taken.contains($0.path) })
        XCTAssertEqual(name, "Ролик (3)")
    }

    func testUniqueBaseKeepsNameWhenFree() {
        let name = FileNaming.uniqueBase(directory: URL(fileURLWithPath: "/tmp"), base: "Новый",
                                         extensions: ["mp4"], exists: { _ in false })
        XCTAssertEqual(name, "Новый")
    }
}

/// Приложение из Finder получает урезанный PATH без Homebrew. yt-dlp ищет Deno именно
/// в PATH, поэтому путь к нему надо передавать явно — иначе YouTube отдаёт раскадровки.
final class JSRuntimeArgumentTests: XCTestCase {

    func testToolchainBuildsRuntimeArgument() {
        let chain = Toolchain(jsRuntime: URL(fileURLWithPath: "/opt/homebrew/bin/deno"))
        XCTAssertEqual(chain.jsRuntimeArgument, "deno:/opt/homebrew/bin/deno")
        XCTAssertNil(Toolchain().jsRuntimeArgument)
    }

    func testBothCommandsCarryTheRuntime() {
        let runtime = "deno:/opt/homebrew/bin/deno"

        let info = YtDlpArguments.metadata(url: "u", jsRuntime: runtime)
        XCTAssertEqual(index(of: "--js-runtimes", in: info).map { info[$0 + 1] }, runtime)

        let plan = DownloadPlan(mode: .video, selector: "137+140", container: "mp4")
        let download = YtDlpArguments.download(plan: plan, url: "u", basePath: "/tmp/a",
                                               ffmpegDirectory: "/opt/homebrew/bin",
                                               jsRuntime: runtime)
        XCTAssertEqual(index(of: "--js-runtimes", in: download).map { download[$0 + 1] }, runtime)
    }

    func testWithoutRuntimeNoFlagIsAdded() {
        XCTAssertFalse(YtDlpArguments.metadata(url: "u").contains("--js-runtimes"))
        XCTAssertTrue(YtDlpArguments.jsRuntime(nil).isEmpty)
    }

    private func index(of flag: String, in args: [String]) -> Int? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? $0 : nil }
    }
}
