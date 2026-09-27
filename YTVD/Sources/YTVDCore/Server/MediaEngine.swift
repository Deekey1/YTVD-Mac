import Foundation

/// Что умеет движок на этой машине.
public struct EngineCapabilities: Sendable, Equatable {
    public var canMerge: Bool
    public var canTranscode: Bool
    public init(canMerge: Bool, canTranscode: Bool) {
        self.canMerge = canMerge; self.canTranscode = canTranscode
    }
}

/// Движок, которым пользуется сервер заданий. Протокол нужен ради тестов:
/// задания проверяются на подставном движке, без сети и yt-dlp.
public protocol MediaEngine: AnyObject, Sendable {
    var capabilities: EngineCapabilities { get }
    var versions: (ytdlp: String?, ffmpeg: String?, js: String?) { get }

    func resolve(url: URL) async throws -> MediaService.Resolved
    func download(plan: DownloadPlan, url: URL, directory: URL, baseName: String,
                  onEvent: @escaping @Sendable (MediaService.Event) -> Void) async throws -> MediaService.DownloadResult
    func transcode(input: URL, output: URL, spec: TranscodeSpec, duration: Double?,
                   onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// Прервать то, что этот экземпляр сейчас делает.
    func cancel()
}

/// Настоящий движок: тот же MediaService, что у Mac-приложения, плюс ffmpeg для HEVC.
public final class YtDlpEngine: MediaEngine, @unchecked Sendable {

    private let toolchain: Toolchain
    private let service: MediaService
    private let lock = NSLock()
    private var transcoder: RunningProcess?
    private var cancelled = false

    public init(toolchain: Toolchain, network: NetworkOptions = .none) {
        self.toolchain = toolchain
        self.service = MediaService(toolchain: toolchain, network: network)
    }

    public var capabilities: EngineCapabilities {
        EngineCapabilities(canMerge: toolchain.canMerge, canTranscode: Self.hardwareHEVC(toolchain))
    }

    public var versions: (ytdlp: String?, ffmpeg: String?, js: String?) {
        (toolchain.ytdlpVersion, toolchain.ffmpegVersion, toolchain.jsRuntime?.lastPathComponent)
    }

    public func resolve(url: URL) async throws -> MediaService.Resolved {
        try await service.fetchInfo(url: url)
    }

    public func download(plan: DownloadPlan, url: URL, directory: URL, baseName: String,
                         onEvent: @escaping @Sendable (MediaService.Event) -> Void) async throws -> MediaService.DownloadResult {
        try await service.download(plan: plan, url: url, directory: directory,
                                   baseName: baseName, onEvent: onEvent)
    }

    /// Перекодирование в HEVC аппаратным кодировщиком. Звук AAC копируется как есть.
    public func transcode(input: URL, output: URL, spec: TranscodeSpec, duration: Double?,
                          onProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard let ffmpeg = toolchain.ffmpeg else { throw YTVDError.toolMissing("ffmpeg") }

        let args = Self.transcodeArguments(input: input.path, output: output.path, spec: spec)
        let total = (duration ?? 0) * 1_000_000
        var lastError = ""

        let status = try await ProcessRunner.stream(
            ffmpeg, args,
            started: { [weak self] handle in self?.setTranscoder(handle) },
            onStdout: { line in
                // -progress pipe:1 печатает пары «ключ=значение».
                guard total > 0, line.hasPrefix("out_time_us="),
                      let value = Double(line.dropFirst("out_time_us=".count)) else { return }
                onProgress(min(1, max(0, value / total)))
            },
            onStderr: { line in
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { lastError = line }
            })
        setTranscoder(nil)

        if isCancelled { throw YTVDError.cancelled }
        guard status == 0 else {
            try? FileManager.default.removeItem(at: output)
            throw YTVDError.tool("Не удалось перекодировать видео: \(lastError)")
        }
    }

    /// Аргументы ffmpeg. Тег hvc1 обязателен: без него QuickTime и iPhone не узнают HEVC.
    static func transcodeArguments(input: String, output: String, spec: TranscodeSpec) -> [String] {
        [
            "-hide_banner", "-nostdin", "-y",
            "-i", input,
            "-map", "0:v:0", "-map", "0:a:0?",
            "-c:v", spec.encoder, "-b:v", "\(spec.bitrate)", "-allow_sw", "1",
            "-tag:v", "hvc1", "-pix_fmt", "yuv420p",
            "-c:a", "copy",
            "-movflags", "+faststart",
            "-progress", "pipe:1", "-nostats",
            output,
        ]
    }

    /// Есть ли в ffmpeg аппаратный HEVC. Спрашиваем один раз на путь к ffmpeg.
    private static var encoderCache: [String: Bool] = [:]
    private static let cacheLock = NSLock()

    static func hardwareHEVC(_ toolchain: Toolchain) -> Bool {
        guard let ffmpeg = toolchain.ffmpeg else { return false }
        cacheLock.lock()
        if let cached = encoderCache[ffmpeg.path] { cacheLock.unlock(); return cached }
        cacheLock.unlock()

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-encoders"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var found = false
        if (try? process.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            found = String(decoding: data, as: UTF8.self).contains("hevc_videotoolbox")
        }
        cacheLock.lock(); encoderCache[ffmpeg.path] = found; cacheLock.unlock()
        return found
    }

    public func cancel() {
        lock.lock(); cancelled = true; let handle = transcoder; lock.unlock()
        service.cancel()
        handle?.terminate()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    private func setTranscoder(_ handle: RunningProcess?) {
        lock.lock(); transcoder = handle; lock.unlock()
    }
}
