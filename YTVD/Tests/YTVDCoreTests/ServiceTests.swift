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
        XCTAssertEqual(empty.summary, "yt-dlp не найден · ffmpeg не найден")

        let full = Toolchain(ytdlp: URL(fileURLWithPath: "/x/yt-dlp"),
                             ffmpeg: URL(fileURLWithPath: "/x/ffmpeg"),
                             ytdlpVersion: "2025.04.30", ffmpegVersion: "7.1.1")
        XCTAssertTrue(full.isReady)
        XCTAssertTrue(full.canMerge)
        XCTAssertEqual(full.summary, "yt-dlp 2025.04.30 · ffmpeg 7.1.1")
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
