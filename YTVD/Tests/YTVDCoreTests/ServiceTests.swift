import XCTest
@testable import YTVDCore

final class BinaryLocatorTests: XCTestCase {

    func testFindsFirstMatchingDirectory() {
        let dirs = [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")]
        let found = BinaryLocator.find("yt-dlp", in: dirs) { $0.path == "/b/yt-dlp" }
        XCTAssertEqual(found?.path, "/b/yt-dlp")
    }

    func testPrefersEarlierDirectory() {
        let dirs = [URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")]
        let found = BinaryLocator.find("yt-dlp", in: dirs) { _ in true }
        XCTAssertEqual(found?.path, "/a/yt-dlp")
    }

    func testReturnsNilWhenMissing() {
        XCTAssertNil(BinaryLocator.find("yt-dlp", in: [URL(fileURLWithPath: "/a")]) { _ in false })
    }

    func testSearchListIncludesHomebrewAndLocalBin() {
        let paths = BinaryLocator.searchDirectories().map(\.path)
        XCTAssertTrue(paths.contains("/opt/homebrew/bin"))
        XCTAssertTrue(paths.contains("/usr/local/bin"))
        XCTAssertTrue(paths.contains(NSHomeDirectory() + "/.local/bin"))
    }
}

final class ToolchainTests: XCTestCase {

    func testParsesFfmpegVersion() {
        let output = "ffmpeg version 7.1.1 Copyright (c) 2000-2025 the FFmpeg developers\nbuilt with ..."
        XCTAssertEqual(Toolchain.parseFfmpegVersion(output), "7.1.1")
    }

    func testRejectsUnexpectedOutput() {
        XCTAssertNil(Toolchain.parseFfmpegVersion("command not found"))
        XCTAssertNil(Toolchain.parseFfmpegVersion(""))
    }

    func testReadinessFlags() {
        let empty = Toolchain()
        XCTAssertFalse(empty.isReady)
        XCTAssertFalse(empty.canMerge)
        XCTAssertEqual(empty.summary, "yt-dlp не найден · ffmpeg не найден · deno не найден")

        let full = Toolchain(ytdlp: URL(fileURLWithPath: "/x/yt-dlp"),
                             ffmpeg: URL(fileURLWithPath: "/x/ffmpeg"),
                             ytdlpVersion: "2025.04.30", ffmpegVersion: "7.1.1")
        XCTAssertTrue(full.isReady)
        XCTAssertTrue(full.canMerge)
        XCTAssertEqual(full.summary, "yt-dlp 2025.04.30 · ffmpeg 7.1.1 · deno не найден")
    }
}

final class NetworkEnvironmentTests: XCTestCase {

    func testRecognisesTunnelInterfaces() {
        for name in ["utun0", "utun5", "ipsec0", "ppp0", "tun1"] {
            XCTAssertTrue(NetworkEnvironment.isTunnel(name), "\(name) — туннель")
        }
    }

    func testOrdinaryInterfacesAreNotTunnels() {
        for name in ["en0", "en1", "bridge0", "lo0", nil] {
            XCTAssertFalse(NetworkEnvironment.isTunnel(name), "\(name ?? "nil") — не туннель")
        }
    }

    func testPrimaryInterfaceIsReadable() {
        // На живой машине интерфейс должен определяться (имя зависит от сети).
        let name = NetworkEnvironment.primaryInterface()
        XCTAssertNotNil(name)
        XCTAssertFalse(name?.isEmpty ?? true)
    }
}

final class MediaServiceTests: XCTestCase {

    func testDecodesPlainInfo() throws {
        let json = """
        {"id":"abc","title":"Ролик","uploader":"Канал","duration":632.0,
         "thumbnail":"https://i/1.jpg","view_count":4200000,"upload_date":"20230114",
         "formats":[{"format_id":"137","ext":"mp4","vcodec":"avc1.640028","acodec":"none",
                     "height":1080,"filesize":320000000,"tbr":4100.0}]}
        """
        let info = try MediaService.decodeInfo(from: Data(json.utf8))
        XCTAssertEqual(info.title, "Ролик")
        XCTAssertEqual(info.formats?.count, 1)
        XCTAssertEqual(info.formats?.first?.height, 1080)
        XCTAssertEqual(info.view_count, 4_200_000)
    }

    func testDecodesFirstEntryOfPlaylist() throws {
        let json = """
        {"_type":"playlist","entries":[
          {"id":"noformats","title":"Пусто"},
          {"id":"good","title":"Второй","formats":[{"format_id":"18","height":360}]}]}
        """
        let info = try MediaService.decodeInfo(from: Data(json.utf8))
        XCTAssertEqual(info.id, "good")
    }

    func testUnknownJSONThrows() {
        XCTAssertThrowsError(try MediaService.decodeInfo(from: Data("[1,2,3]".utf8)))
    }

    func testResolveOutputPrefersMergedFile() {
        let plan = DownloadPlan(mode: .video, selector: "137+140", container: "mp4")
        let file = MediaService.resolveOutput(
            destinations: ["/tmp/Ролик.f137.mp4", "/tmp/Ролик.f140.m4a", "/tmp/Ролик.mp4"],
            directory: URL(fileURLWithPath: "/tmp"), baseName: "Ролик", plan: plan,
            contents: { _ in [] })
        XCTAssertEqual(file?.lastPathComponent, "Ролик.mp4")
    }

    func testResolveOutputFallsBackToDirectoryScan() {
        let plan = DownloadPlan(mode: .audioMP3, selector: "bestaudio", container: "mp3")
        let file = MediaService.resolveOutput(
            destinations: ["/tmp/Ролик.webm"],
            directory: URL(fileURLWithPath: "/tmp"), baseName: "Ролик", plan: plan,
            contents: { _ in [URL(fileURLWithPath: "/tmp/Ролик.mp3"),
                              URL(fileURLWithPath: "/tmp/Другой.mp4")] })
        XCTAssertEqual(file?.lastPathComponent, "Ролик.mp3")
    }

    func testPhaseTrackerNamesStreams() {
        let merged = PhaseTracker(plan: DownloadPlan(mode: .video, selector: "137+140", container: "mp4"))
        XCTAssertEqual(merged.advance(destination: "a.f137.mp4"), "видео")
        XCTAssertEqual(merged.advance(destination: "a.f140.m4a"), "аудио")

        let single = PhaseTracker(plan: DownloadPlan(mode: .video, selector: "18", container: "mp4"))
        XCTAssertEqual(single.advance(destination: "a.mp4"), "видео")

        let audio = PhaseTracker(plan: DownloadPlan(mode: .audioMP3, selector: "bestaudio", container: "mp3"))
        XCTAssertEqual(audio.advance(destination: "a.webm"), "аудио")
    }
}

final class ProcessRunnerTests: XCTestCase {

    func testRunsCommandAndCollectsOutput() async throws {
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/echo"), ["привет"])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "привет")
    }

    func testCollectsManyLinesInOrder() async throws {
        let script = "for i in $(seq 1 200); do echo line$i; done"
        var lines: [String] = []
        let status = try await ProcessRunner.stream(URL(fileURLWithPath: "/bin/sh"), ["-c", script],
                                                    onStdout: { lines.append($0) })
        XCTAssertEqual(status, 0)
        XCTAssertEqual(lines.count, 200)
        XCTAssertEqual(lines.first, "line1")
        XCTAssertEqual(lines.last, "line200")
    }

    func testSeparatesStderrAndReportsExitCode() async throws {
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"),
                                                 ["-c", "echo out; echo err 1>&2; exit 3"])
        XCTAssertEqual(result.status, 3)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.stdout.contains("out"))
        XCTAssertTrue(result.stderr.contains("err"))
    }

    func testMissingExecutableThrows() async {
        do {
            _ = try await ProcessRunner.run(URL(fileURLWithPath: "/nope/nothing"), [])
            XCTFail("ожидали ошибку запуска")
        } catch {
            XCTAssertTrue(error is YTVDError)
        }
    }

    func testTerminationIsReported() async throws {
        var handle: RunningProcess?
        let task = Task {
            try await ProcessRunner.stream(URL(fileURLWithPath: "/bin/sleep"), ["30"],
                                           started: { handle = $0 },
                                           onStdout: { _ in })
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        handle?.terminate()
        let status = try await task.value
        XCTAssertNotEqual(status, 0, "прерванный процесс не должен возвращать успех")
    }
}

/// YouTube решает задачу на JavaScript: без исполнителя список форматов приходит пустым.
final class JSRuntimeTests: XCTestCase {

    func testToolchainReportsMissingRuntime() {
        let chain = Toolchain(ytdlp: URL(fileURLWithPath: "/x/yt-dlp"),
                              ffmpeg: URL(fileURLWithPath: "/x/ffmpeg"))
        XCTAssertFalse(chain.canSolveYouTube)
        XCTAssertTrue(chain.summary.contains("deno не найден"))

        let full = Toolchain(ytdlp: URL(fileURLWithPath: "/x/yt-dlp"),
                             ffmpeg: URL(fileURLWithPath: "/x/ffmpeg"),
                             jsRuntime: URL(fileURLWithPath: "/x/deno"))
        XCTAssertTrue(full.canSolveYouTube)
        XCTAssertTrue(full.summary.contains("deno"))
    }

    func testEmptyFormatListIsBlamedOnRuntimeNotOnQuality() {
        let raw = "ERROR: Requested format is not available"
        let withoutJS = YtDlpOutput.humanError(raw, source: .youtube, hasJSRuntime: false)
        XCTAssertTrue(withoutJS.contains("brew install deno"), "получили: \(withoutJS)")

        let withJS = YtDlpOutput.humanError(raw, source: .youtube, hasJSRuntime: true)
        XCTAssertTrue(withJS.contains("другое качество"), "получили: \(withJS)")
    }

    func testChallengeWarningIsRecognisedDirectly() {
        for raw in ["n challenge solving failed: Some formats may be missing",
                    "Only images are available for download"] {
            XCTAssertTrue(YtDlpOutput.humanError(raw, source: .youtube).contains("deno"),
                          "не распознано: \(raw)")
        }
    }
}

/// Обновление движка предлагается только тогда, когда сбой действительно на него похож.
final class EngineUpdaterTests: XCTestCase {

    func testRecognisesEngineBreakage() {
        for raw in ["ERROR: Requested format is not available",
                    "ERROR: Unable to extract player response",
                    "WARNING: nsig extraction failed",
                    "Only images are available for download",
                    "n challenge solving failed",
                    "Confirm you are on the latest version using yt-dlp -U"] {
            XCTAssertTrue(YtDlpOutput.looksLikeEngineBreakage(raw), "не распознано: \(raw)")
        }
    }

    /// Обновление не поможет: дело в доступе, правах или самой ссылке.
    func testDoesNotBlameEngineForAccessProblems() {
        for raw in ["ERROR: Video unavailable",
                    "ERROR: Private video",
                    "PrivacyError: We're having a little trouble",
                    "The web client only works when logged-in",
                    "Got HTTP Error 403 ... data center IP or VPN/proxy",
                    "unable to download video data: [Errno 61] Connection refused",
                    "ERROR: Unsupported URL: https://example.com"] {
            XCTAssertFalse(YtDlpOutput.looksLikeEngineBreakage(raw), "ложная тревога: \(raw)")
        }
    }

    func testVersionComparison() {
        XCTAssertTrue(EngineUpdater.isNewer("2026.08.09", than: "2026.07.04"))
        XCTAssertTrue(EngineUpdater.isNewer("2026.07.04.1", than: "2026.07.04"))
        XCTAssertTrue(EngineUpdater.isNewer("2027.01.01", than: "2026.12.31"))
        XCTAssertFalse(EngineUpdater.isNewer("2026.07.04", than: "2026.07.04"))
        XCTAssertFalse(EngineUpdater.isNewer("2026.06.01", than: "2026.07.04"))
        XCTAssertTrue(EngineUpdater.isNewer("2026.07.04", than: nil), "версия неизвестна — считаем новее")
    }

    /// В сеть не ходим на каждый сбой: подряд идущие ошибки не должны дёргать GitHub.
    func testCheckIsThrottled() {
        let suite = UserDefaults(suiteName: "ytvd.tests.\(UUID().uuidString)")!
        let now = Date()

        XCTAssertTrue(EngineUpdater.shouldCheck(now: now, defaults: suite), "первая проверка разрешена")
        EngineUpdater.rememberCheck(now: now, defaults: suite)

        XCTAssertFalse(EngineUpdater.shouldCheck(now: now.addingTimeInterval(60), defaults: suite))
        XCTAssertFalse(EngineUpdater.shouldCheck(now: now.addingTimeInterval(3600), defaults: suite))
        XCTAssertTrue(EngineUpdater.shouldCheck(now: now.addingTimeInterval(7 * 3600), defaults: suite))
    }

    func testDownloadsLandNextToSettings() {
        XCTAssertTrue(EngineUpdater.directory.path.contains("Application Support/YTVD/bin"))
        XCTAssertEqual(BinaryLocator.searchDirectories().first, EngineUpdater.directory,
                       "скачанное обновление важнее и встроенного, и системного")
    }

    /// Распакованная сборка встаёт на место старого однофайлового yt-dlp: bin/yt-dlp — ссылка
    /// на исполняемый файл в папке сборки, и приложение находит его по прежнему имени.
    func testOnedirBuildReplacesOnefileAndIsFound() async throws {
        let root = makeTemporaryDirectory()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try "старый однофайловый".write(to: bin.appendingPathComponent("yt-dlp"), atomically: true, encoding: .utf8)
        let bundle = try fakeOnedir(in: root, version: "2099.01.02")

        let installed = try await EngineUpdater.activateYtDlp(bundle, in: bin)

        XCTAssertEqual(installed.lastPathComponent, "yt-dlp")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: installed.path),
                       "yt-dlp_macos-2099.01.02/yt-dlp_macos", "ссылка относительная — папку можно переносить")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: bin.appendingPathComponent("yt-dlp_macos-2099.01.02/_internal").path),
                      "библиотеки лежат рядом с исполняемым файлом")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundle.path), "распакованное перенесено, а не скопировано")
        XCTAssertEqual(BinaryLocator.find("yt-dlp", in: [bin])?.path, installed.path)
        let output = try await ProcessRunner.run(installed, ["--version"])
        XCTAssertEqual(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "2099.01.02")
    }

    /// Обновление переключает ссылку на новую сборку, а предыдущую не трогает: ею может ещё
    /// качать начатое задание. Следующее обновление убирает ту, что старше предыдущей.
    func testUpdateKeepsPreviousBuildUntilTheNextOne() async throws {
        let root = makeTemporaryDirectory()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        func builds() throws -> Set<String> {
            Set(try FileManager.default.contentsOfDirectory(atPath: bin.path).filter { $0.hasPrefix("yt-dlp_macos") })
        }
        _ = try await EngineUpdater.activateYtDlp(try fakeOnedir(in: root, name: "a", version: "2099.01.01"), in: bin)
        let installed = try await EngineUpdater.activateYtDlp(
            try fakeOnedir(in: root, name: "b", version: "2099.02.02"), in: bin)

        let output = try await ProcessRunner.run(installed, ["--version"])
        XCTAssertEqual(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "2099.02.02")
        XCTAssertEqual(try builds(), ["yt-dlp_macos-2099.01.01", "yt-dlp_macos-2099.02.02"])

        _ = try await EngineUpdater.activateYtDlp(try fakeOnedir(in: root, name: "c", version: "2099.03.03"), in: bin)
        XCTAssertEqual(try builds(), ["yt-dlp_macos-2099.02.02", "yt-dlp_macos-2099.03.03"])
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: bin.path).contains { $0.hasPrefix(".yt-dlp-") },
                       "временная ссылка не остаётся")
    }

    /// Та же версия ещё раз (переустановка) — рядом, в своей папке, а ссылка на новую.
    func testReinstallingSameVersionGetsItsOwnFolder() async throws {
        let root = makeTemporaryDirectory()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        _ = try await EngineUpdater.activateYtDlp(try fakeOnedir(in: root, name: "a", version: "2099.01.01"), in: bin)
        let installed = try await EngineUpdater.activateYtDlp(
            try fakeOnedir(in: root, name: "b", version: "2099.01.01"), in: bin)

        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: installed.path)
        XCTAssertTrue(destination.hasPrefix("yt-dlp_macos-2099.01.01-"), destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bin.appendingPathComponent("yt-dlp_macos-2099.01.01").path))
    }

    /// Скачанная сборка не запускается — прежняя остаётся как была.
    func testBrokenBuildKeepsPreviousOne() async throws {
        let root = makeTemporaryDirectory()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        _ = try await EngineUpdater.activateYtDlp(try fakeOnedir(in: root, name: "good", version: "2099.01.01"), in: bin)

        do {
            _ = try await EngineUpdater.activateYtDlp(
                try fakeOnedir(in: root, name: "broken", version: "", exitCode: 1), in: bin)
            XCTFail("сломанная сборка не должна встать на место")
        } catch {}

        let output = try await ProcessRunner.run(bin.appendingPathComponent("yt-dlp"), ["--version"])
        XCTAssertEqual(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "2099.01.01")
    }

    func testArchiveWithoutExecutableIsRejected() async throws {
        let root = makeTemporaryDirectory()
        let empty = root.appendingPathComponent("yt-dlp_macos")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        do {
            _ = try await EngineUpdater.activateYtDlp(empty, in: root.appendingPathComponent("bin"))
            XCTFail("без исполняемого файла ставить нечего")
        } catch {}
    }

    /// Папка как в yt-dlp_macos.zip: исполняемый файл и _internal рядом. Вместо Python — скрипт.
    private func fakeOnedir(in root: URL, name: String = "unpacked", version: String,
                            exitCode: Int = 0) throws -> URL {
        let bundle = root.appendingPathComponent(name).appendingPathComponent("yt-dlp_macos")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("_internal"),
                                                withIntermediateDirectories: true)
        let executable = bundle.appendingPathComponent("yt-dlp_macos")
        try "#!/bin/sh\necho \(version)\nexit \(exitCode)\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return bundle
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ytvd-engine-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Обновление самой программы: сравнение версий и разбор ответа GitHub.
final class AppUpdaterTests: XCTestCase {

    func testTagComparison() {
        XCTAssertTrue(EngineUpdater.isNewer("1.2", than: "1.1"))
        XCTAssertTrue(EngineUpdater.isNewer("1.10", than: "1.9"), "1.10 новее 1.9, а не наоборот")
        XCTAssertTrue(EngineUpdater.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(EngineUpdater.isNewer("1.1", than: "1.1"))
        XCTAssertFalse(EngineUpdater.isNewer("1.0.2", than: "1.1"))
    }

    func testCurrentVersionIsReadable() {
        // Вне бандла Info.plist нет — тогда версия считается нулевой и любая новее.
        XCTAssertFalse(AppUpdater.currentVersion.isEmpty)
        XCTAssertTrue(EngineUpdater.isNewer("1.2", than: "0"))
    }

    func testRepositoryPointsAtTheRightProject() {
        XCTAssertEqual(AppUpdater.repository, "Deekey1/YTVD-Mac")
    }
}
