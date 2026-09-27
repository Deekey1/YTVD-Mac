import Foundation
@testable import YTVDCore

/// Подставной движок: пишет файлы и шлёт события как настоящий, но без сети и yt-dlp.
final class FakeEngine: MediaEngine, @unchecked Sendable {

    /// Общее состояние всех экземпляров — сервер создаёт движок на каждое задание.
    final class Shared: @unchecked Sendable {
        private let lock = NSLock()
        private var _resolves = 0
        private var _released = true
        private var _transcodes = 0
        var info: MediaInfo
        var failDownload: Error?
        var failResolve: Error?
        var capabilities = EngineCapabilities(canMerge: true, canTranscode: true)
        var fileBytes = 4096

        init(info: MediaInfo) { self.info = info }

        var resolves: Int { lock.lock(); defer { lock.unlock() }; return _resolves }
        var transcodes: Int { lock.lock(); defer { lock.unlock() }; return _transcodes }
        func countResolve() { lock.lock(); _resolves += 1; lock.unlock() }
        func countTranscode() { lock.lock(); _transcodes += 1; lock.unlock() }

        /// Закрытый шлагбаум держит загрузку — для проверки очереди и отмены.
        var released: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _released }
            set { lock.lock(); _released = newValue; lock.unlock() }
        }
    }

    let shared: Shared
    private let lock = NSLock()
    private var cancelled = false

    init(_ shared: Shared) { self.shared = shared }

    var capabilities: EngineCapabilities { shared.capabilities }
    var versions: (ytdlp: String?, ffmpeg: String?, js: String?) { ("2026.07.04", "8.1", "deno") }

    func resolve(url: URL) async throws -> MediaService.Resolved {
        shared.countResolve()
        if let error = shared.failResolve { throw error }
        return MediaService.Resolved(info: shared.info, url: url)
    }

    func download(plan: DownloadPlan, url: URL, directory: URL, baseName: String,
                  onEvent: @escaping @Sendable (MediaService.Event) -> Void) async throws -> MediaService.DownloadResult {
        onEvent(.phase("видео"))
        onEvent(.progress(DownloadProgress(downloaded: 1000, total: 4000, speed: 2_000_000, eta: 3)))

        while !shared.released {
            if isCancelled { throw YTVDError.cancelled }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if isCancelled { throw YTVDError.cancelled }
        if let error = shared.failDownload { throw error }

        onEvent(.phase("аудио"))
        onEvent(.phase("склейка"))
        let file = directory.appendingPathComponent("\(baseName).\(plan.container)")
        try FakeEngine.pattern(shared.fileBytes).write(to: file)
        return MediaService.DownloadResult(file: file, bytes: Int64(shared.fileBytes))
    }

    func transcode(input: URL, output: URL, spec: TranscodeSpec, duration: Double?,
                   onProgress: @escaping @Sendable (Double) -> Void) async throws {
        shared.countTranscode()
        onProgress(0.5)
        try FileManager.default.copyItem(at: input, to: output)
        onProgress(1)
    }

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }

    /// Содержимое «скачанного» файла: байты не повторяются подряд, так что по куску видно, откуда он.
    static func pattern(_ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 % 251) })
    }

    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

enum Fixtures {
    static func youtube4K() throws -> MediaInfo {
        let url = Bundle.module.url(forResource: "youtube-4k", withExtension: "json", subdirectory: "Fixtures")!
        return try JSONDecoder().decode(MediaInfo.self, from: Data(contentsOf: url))
    }

    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytvd-server-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
