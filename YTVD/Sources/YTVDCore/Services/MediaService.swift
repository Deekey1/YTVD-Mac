import Foundation

/// Обёртка над yt-dlp: получение сведений и скачивание.
public final class MediaService: @unchecked Sendable {

    private let toolchain: Toolchain
    private var current: RunningProcess?
    private let lock = NSLock()

    /// Сетевые настройки берутся при каждом запуске: их можно менять на ходу.
    private var storedNetwork: NetworkOptions

    public init(toolchain: Toolchain, network: NetworkOptions = .none) {
        self.toolchain = toolchain
        self.storedNetwork = network
    }

    public func configure(network: NetworkOptions) {
        lock.lock(); storedNetwork = network; lock.unlock()
    }

    private var network: NetworkOptions {
        lock.lock(); defer { lock.unlock() }
        return storedNetwork
    }

    // MARK: - сведения о ролике

    /// Что получилось разобрать и по какой ссылке — качать нужно по ней же.
    public struct Resolved: Sendable {
        public let info: MediaInfo
        public let url: URL
    }

    public func fetchInfo(url: URL) async throws -> Resolved {
        var failure: (raw: String, url: URL)?

        // Для Vimeo вторая попытка идёт через страницу плеера: главную он закрывает.
        for candidate in VimeoLinks.candidates(for: url) {
            do {
                return Resolved(info: try await fetchOnce(url: candidate), url: candidate)
            } catch let error as RawToolFailure {
                failure = (error.raw, candidate)
                // Пробовать запасной путь есть смысл только когда закрыт доступ.
                guard YtDlpOutput.isAddressRelated(error.raw) else { break }
            }
        }

        throw YTVDError.tool(YtDlpOutput.humanError(
            failure?.raw ?? "",
            source: MediaSource.detect(url),
            viaVPN: NetworkEnvironment.isUsingVPN,
            hasCookies: network.cookiesFromBrowser != nil,
            canMerge: toolchain.canMerge,
                hasJSRuntime: toolchain.canSolveYouTube))
    }

    /// Сырая неудача запуска: текст от yt-dlp нужен целиком, чтобы решить, пробовать ли дальше.
    private struct RawToolFailure: Error { let raw: String }

    private func fetchOnce(url: URL) async throws -> MediaInfo {
        guard let ytdlp = toolchain.ytdlp else { throw YTVDError.toolMissing("yt-dlp") }

        var stdout = ""
        var stderr = ""
        let status = try await ProcessRunner.stream(
            ytdlp, YtDlpArguments.metadata(url: url.absoluteString, network: network,
                                    jsRuntime: toolchain.jsRuntimeArgument),
            started: { [weak self] handle in self?.setCurrent(handle) },
            onStdout: { stdout += $0 },
            onStderr: { stderr += $0 + "\n" })
        setCurrent(nil)

        guard status == 0, let data = stdout.data(using: .utf8), !data.isEmpty else {
            throw RawToolFailure(raw: Self.firstError(in: stderr))
        }
        return try Self.decodeInfo(from: data)
    }

    /// Из потока stderr выбираем строку, которая действительно объясняет отказ.
    static func firstError(in stderr: String) -> String {
        let lines = stderr.split(separator: "\n").map(String.init)
        if let explicit = lines.first(where: { $0.hasPrefix("ERROR:") }) { return explicit }
        return lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
    }

    /// yt-dlp иногда отдаёт плейлист даже с --no-playlist (например, ссылка на канал).
    static func decodeInfo(from data: Data) throws -> MediaInfo {
        let decoder = JSONDecoder()
        if let info = try? decoder.decode(MediaInfo.self, from: data),
           info.formats?.isEmpty == false {
            return info
        }
        struct Playlist: Decodable { let entries: [MediaInfo]? }
        if let playlist = try? decoder.decode(Playlist.self, from: data),
           let first = playlist.entries?.first(where: { $0.formats?.isEmpty == false }) {
            return first
        }
        if let info = try? decoder.decode(MediaInfo.self, from: data) {
            return info                                  // без форматов — покажем ошибку выше
        }
        throw YTVDError.tool("Не удалось разобрать ответ yt-dlp")
    }

    // MARK: - скачивание

    public struct DownloadResult: Sendable {
        public let file: URL
        public let bytes: Int64
    }

    /// События по ходу скачивания.
    public enum Event: Sendable {
        case phase(String)
        case progress(DownloadProgress)
    }

    public func download(plan: DownloadPlan, url: URL, directory: URL, baseName: String,
                         onEvent: @escaping @Sendable (Event) -> Void) async throws -> DownloadResult {
        guard let ytdlp = toolchain.ytdlp else { throw YTVDError.toolMissing("yt-dlp") }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let basePath = directory.appendingPathComponent(baseName).path

        let args = YtDlpArguments.download(
            plan: plan, url: url.absoluteString, basePath: basePath,
            ffmpegDirectory: toolchain.ffmpeg?.deletingLastPathComponent().path,
            network: network,
            jsRuntime: toolchain.jsRuntimeArgument)

        let tracker = PhaseTracker(plan: plan)
        var lastError = ""
        var destinations: [String] = []

        let status = try await ProcessRunner.stream(
            ytdlp, args,
            started: { [weak self] handle in self?.setCurrent(handle) },
            onStdout: { line in
                switch YtDlpOutput.classify(line) {
                case .progress(let progress):
                    onEvent(.progress(progress))
                case .destination(let path):
                    destinations.append(path)
                    onEvent(.phase(tracker.advance(destination: path)))
                case .merging(let path):
                    if !path.isEmpty { destinations.append(path) }
                    onEvent(.phase("склейка"))
                case .extractingAudio:
                    onEvent(.phase("перекодирование"))
                case .embeddingThumbnail:
                    onEvent(.phase("обложка в теги"))
                case .alreadyDownloaded(let path):
                    destinations.append(path)
                case .failure(let message):
                    lastError = message
                case .other:
                    break
                }
            },
            onStderr: { line in
                if case .failure(let message) = YtDlpOutput.classify(line) { lastError = message }
                else if !line.trimmingCharacters(in: .whitespaces).isEmpty { lastError = line }
            })
        setCurrent(nil)

        if status != 0 {
            if status == 15 || status == 2 { throw YTVDError.cancelled }   // SIGTERM
            throw YTVDError.tool(YtDlpOutput.humanError(
                lastError,
                source: MediaSource.detect(url),
                viaVPN: NetworkEnvironment.isUsingVPN,
                hasCookies: network.cookiesFromBrowser != nil,
                canMerge: toolchain.canMerge,
                hasJSRuntime: toolchain.canSolveYouTube))
        }

        let file = Self.resolveOutput(destinations: destinations, directory: directory,
                                      baseName: baseName, plan: plan)
        guard let file else { throw YTVDError.tool("Файл скачался, но найти его не удалось") }

        let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
        return DownloadResult(file: file, bytes: bytes ?? 0)
    }

    /// Ищем итоговый файл: сначала среди путей из вывода, затем по имени в папке.
    static func resolveOutput(destinations: [String], directory: URL, baseName: String,
                              plan: DownloadPlan,
                              contents: ((URL) -> [URL])? = nil) -> URL? {
        let list = contents ?? { url in
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        }

        // Итоговый файл — тот, что с ожидаемым расширением и без пометки потока (.f137.).
        let expected = plan.container
        for path in destinations.reversed() {
            let url = URL(fileURLWithPath: path)
            if url.pathExtension.lowercased() == expected.lowercased(),
               !url.deletingPathExtension().lastPathComponent.contains(".f") {
                return url
            }
        }
        let candidates = list(directory).filter {
            $0.deletingPathExtension().lastPathComponent == baseName
        }
        if let exact = candidates.first(where: { $0.pathExtension.lowercased() == expected.lowercased() }) {
            return exact
        }
        return candidates.first ?? destinations.last.map { URL(fileURLWithPath: $0) }
    }

    // MARK: - отмена

    public func cancel() {
        lock.lock(); let handle = current; lock.unlock()
        handle?.terminate()
    }

    private func setCurrent(_ handle: RunningProcess?) {
        lock.lock(); current = handle; lock.unlock()
    }
}

/// Определяет, какой этап идёт сейчас: видео, аудио или склейка.
final class PhaseTracker: @unchecked Sendable {
    private let plan: DownloadPlan
    private var seen = 0

    init(plan: DownloadPlan) { self.plan = plan }

    func advance(destination: String) -> String {
        seen += 1
        switch plan.mode {
        case .video:
            // При склейке двух дорожек yt-dlp сначала качает видео, потом звук.
            let merged = plan.selector.contains("+")
            if !merged { return "видео" }
            return seen == 1 ? "видео" : "аудио"
        case .audioNative, .audioMP3:
            return "аудио"
        case .cover:
            return "обложка"
        }
    }
}
