import XCTest
@testable import YTVDCore

/// Раздел «Сервер для iPhone» в настройках: включение, код, сопряжение, отключение устройств.
@MainActor
final class ServerControllerTests: XCTestCase {

    /// Движок не запускается: для сведений о сервере хватает пути и версии.
    private let toolchain = Toolchain(ytdlp: URL(fileURLWithPath: "/usr/bin/true"), ytdlpVersion: "2026.08.19")

    private func makeSettings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "studio.dk.ytvd.tests.server.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.serverPort = Int.random(in: 20_000...40_000)
        settings.serverBind = "loopback"
        return settings
    }

    private func waitRunning(_ server: ServerController) async throws -> UInt16 {
        for _ in 0..<250 {
            if case .running(let port) = server.status { return port }
            if case .failed(let reason) = server.status { XCTFail(reason); throw CancellationError() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("сервер не запустился")
        throw CancellationError()
    }

    func testEnablePairRevokeDisable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytvd-controller-\(UUID().uuidString)", isDirectory: true)
        let settings = makeSettings()
        let server = ServerController(settings: settings, directory: directory)

        server.apply(toolchain: toolchain)
        XCTAssertEqual(server.status, .off, "выключенный в настройках сервер сам не стартует")

        server.setEnabled(true, toolchain: toolchain)
        XCTAssertTrue(settings.serverEnabled)
        let port = try await waitRunning(server)
        XCTAssertEqual(server.addresses, ["127.0.0.1"])
        XCTAssertTrue(server.statusText.contains("127.0.0.1:\(port)"), server.statusText)

        server.showCode()
        let code = try XCTUnwrap(server.code)
        XCTAssertEqual(code.count, 6)
        XCTAssertTrue((295...300).contains(server.codeSecondsLeft))
        XCTAssertTrue(server.pairingNote.hasPrefix("Введите код"))

        // iPhone вводит код и получает токен.
        var pair = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(API.basePath)/pair")!)
        pair.httpMethod = "POST"
        pair.httpBody = try API.encoder.encode(PairRequest(code: code, deviceName: "iPhone для теста"))
        let (data, response) = try await URLSession.shared.data(for: pair)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let token = try API.decoder.decode(PairResponse.self, from: data).token

        for _ in 0..<100 where server.lastPaired == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(server.lastPaired, "iPhone для теста")
        XCTAssertNil(server.code, "использованный код гаснет на Mac сам")
        XCTAssertEqual(server.pairingNote, "Подключён: iPhone для теста")

        // «Отключить все iPhone»: прежний токен больше не действует.
        server.revokeAll()
        var jobs = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(API.basePath)/jobs")!)
        jobs.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, denied) = try await URLSession.shared.data(for: jobs)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 401)

        // Пока сервер работает, Mac не засыпает; переключатель это отпускает.
        XCTAssertTrue(server.preventsSleep)
        server.setKeepAwake(false)
        XCTAssertFalse(server.preventsSleep)
        server.setKeepAwake(true)
        XCTAssertTrue(server.preventsSleep)

        server.setEnabled(false, toolchain: toolchain)
        XCTAssertEqual(server.status, .off)
        XCTAssertFalse(settings.serverEnabled)
        XCTAssertEqual(server.statusText, "Выключен")
        XCTAssertFalse(server.preventsSleep, "выключенный сервер не держит Mac от сна")
    }

    func testWithoutEngineServerStaysOff() {
        let settings = makeSettings()
        settings.serverEnabled = true
        let server = ServerController(settings: settings, directory: FileManager.default.temporaryDirectory)
        server.apply(toolchain: Toolchain())
        XCTAssertEqual(server.status, .off, "без yt-dlp раздавать нечего")
    }
}
