import Foundation

/// Где приложение ищет yt-dlp и ffmpeg.
///
/// Приложение с графическим интерфейсом не наследует PATH из шелла, поэтому
/// обходим известные каталоги руками: сначала свои, потом системные.
public enum BinaryLocator {

    /// Каталог, куда приложение кладёт скачанный им самим yt-dlp.
    public static var managedDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("YTVD/bin", isDirectory: true)
    }

    /// Каталог внутри бандла — если однажды соберём приложение со всем внутри.
    public static var bundledDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true)
    }

    public static func searchDirectories() -> [URL] {
        // Порядок важен: сначала то, что приложение скачало само (там свежайшее),
        // потом встроенное в бандл, и лишь затем системное.
        var dirs: [URL] = [managedDirectory]
        if let bundled = bundledDirectory { dirs.append(bundled) }
        dirs += [
            "/opt/homebrew/bin",       // Apple Silicon Homebrew
            "/usr/local/bin",          // Intel Homebrew и ручные установки
            "/opt/local/bin",          // MacPorts
            "/usr/bin",
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/bin",
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }
        return dirs
    }

    /// Ищет исполняемый файл по имени. Проверка существования вынесена наружу ради тестов.
    public static func find(_ name: String,
                            in directories: [URL]? = nil,
                            isExecutable: (URL) -> Bool = defaultIsExecutable) -> URL? {
        for directory in directories ?? searchDirectories() {
            let candidate = directory.appendingPathComponent(name)
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    public static func defaultIsExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: url.path)
    }
}

/// Найденные внешние инструменты и их версии.
public struct Toolchain: Sendable, Equatable {
    public var ytdlp: URL?
    public var ffmpeg: URL?
    /// Исполнитель JavaScript. YouTube требует решать задачку на JS, и без него
    /// отдаёт вместо форматов одни раскадровки.
    public var jsRuntime: URL?
    public var ytdlpVersion: String?
    public var ffmpegVersion: String?

    /// Порядок важен: yt-dlp умеет работать с этими, deno — основной.
    public static let jsRuntimeNames = ["deno", "bun", "qjs"]

    public init(ytdlp: URL? = nil, ffmpeg: URL? = nil, jsRuntime: URL? = nil,
                ytdlpVersion: String? = nil, ffmpegVersion: String? = nil) {
        self.ytdlp = ytdlp; self.ffmpeg = ffmpeg; self.jsRuntime = jsRuntime
        self.ytdlpVersion = ytdlpVersion; self.ffmpegVersion = ffmpegVersion
    }

    public var isReady: Bool { ytdlp != nil }

    /// Без ffmpeg нельзя склеивать дорожки и делать MP3 — но готовый файл скачается.
    public var canMerge: Bool { ffmpeg != nil }

    /// Без исполнителя JS YouTube не отдаёт ни одного формата.
    public var canSolveYouTube: Bool { jsRuntime != nil }

    /// Указание для yt-dlp вида `deno:/opt/homebrew/bin/deno`.
    /// Полагаться на PATH нельзя: приложение, запущенное из Finder, получает урезанный.
    public var jsRuntimeArgument: String? {
        guard let jsRuntime else { return nil }
        return "\(jsRuntime.lastPathComponent):\(jsRuntime.path)"
    }

    public var summary: String {
        var parts: [String] = []
        parts.append(ytdlpVersion.map { "yt-dlp \($0)" } ?? "yt-dlp не найден")
        parts.append(ffmpegVersion.map { "ffmpeg \($0)" } ?? "ffmpeg не найден")
        parts.append(jsRuntime.map { $0.lastPathComponent } ?? "deno не найден")
        return parts.joined(separator: " · ")
    }

    public static func discover() async -> Toolchain {
        var chain = Toolchain()
        chain.ytdlp = BinaryLocator.find("yt-dlp")
        chain.ffmpeg = BinaryLocator.find("ffmpeg")
        chain.jsRuntime = jsRuntimeNames.lazy.compactMap { BinaryLocator.find($0) }.first

        if let ytdlp = chain.ytdlp,
           let out = try? await ProcessRunner.run(ytdlp, ["--version"]).stdout {
            chain.ytdlpVersion = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let ffmpeg = chain.ffmpeg,
           let out = try? await ProcessRunner.run(ffmpeg, ["-version"]).stdout {
            chain.ffmpegVersion = parseFfmpegVersion(out)
        }
        return chain
    }

    /// «ffmpeg version 7.1.1 Copyright …» → «7.1.1»
    public static func parseFfmpegVersion(_ output: String) -> String? {
        guard let first = output.split(separator: "\n").first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 3, parts[0] == "ffmpeg", parts[1] == "version" else { return nil }
        return String(parts[2])
    }
}
