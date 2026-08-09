import Foundation

/// Сборка аргументов командной строки. Вынесено отдельно, чтобы проверять тестами
/// без запуска настоящего процесса.
/// Сетевые настройки: чем помочь, когда площадка не пускает.
public struct NetworkOptions: Sendable, Equatable {
    /// Браузер, из которого брать cookies: safari, chrome, firefox…
    public var cookiesFromBrowser: String?
    /// Свой прокси — например, socks5://127.0.0.1:1080.
    public var proxy: String?

    public init(cookiesFromBrowser: String? = nil, proxy: String? = nil) {
        self.cookiesFromBrowser = cookiesFromBrowser?.isEmpty == true ? nil : cookiesFromBrowser
        self.proxy = proxy?.isEmpty == true ? nil : proxy
    }

    public static let none = NetworkOptions()

    public var arguments: [String] {
        var args: [String] = []
        if let cookiesFromBrowser { args += ["--cookies-from-browser", cookiesFromBrowser] }
        if let proxy { args += ["--proxy", proxy] }
        return args
    }
}

public enum YtDlpArguments {

    /// Общие флаги: без плейлистов, с разумными повторами и коротким таймаутом.
    public static let common: [String] = [
        "--no-playlist",
        "--no-warnings",
        "--socket-timeout", "20",
        "--retries", "5",
        "--fragment-retries", "10",
    ]

    /// Где взять исполнитель JavaScript. Приложение из Finder получает урезанный PATH,
    /// в котором Homebrew нет, поэтому путь указываем явно — иначе YouTube отдаёт
    /// вместо форматов одни раскадровки.
    public static func jsRuntime(_ argument: String?) -> [String] {
        argument.map { ["--js-runtimes", $0] } ?? []
    }

    /// Получение сведений о ролике.
    public static func metadata(url: String, network: NetworkOptions = .none,
                                jsRuntime runtime: String? = nil) -> [String] {
        common + network.arguments + jsRuntime(runtime) + ["-J", "--no-progress", url]
    }

    /// Скачивание по выбранному варианту.
    /// - Parameters:
    ///   - basePath: путь без расширения — yt-dlp сам подставит нужное.
    ///   - ffmpegDirectory: каталог с ffmpeg, если он найден.
    public static func download(plan: DownloadPlan, url: String, basePath: String,
                                ffmpegDirectory: String?,
                                network: NetworkOptions = .none,
                                jsRuntime runtime: String? = nil) -> [String] {
        var args = common + network.arguments + jsRuntime(runtime)
        args += ["--newline", "--progress", "--progress-template", "download:" + YtDlpOutput.progressTemplate]
        args += ["--concurrent-fragments", "4"]
        if let ffmpegDirectory { args += ["--ffmpeg-location", ffmpegDirectory] }
        args += ["-o", basePath + ".%(ext)s"]

        switch plan.mode {
        case .video:
            args += ["-f", plan.selector]
            // Склейка и перепаковка — работа ffmpeg; без него эти флаги только помешают.
            if ffmpegDirectory != nil {
                args += ["--merge-output-format", plan.container]
                // Итог всегда должен открываться в QuickTime, если это mp4.
                if plan.container == "mp4" { args += ["--remux-video", "mp4"] }
            }

        case .audioNative:
            args += ["-f", plan.selector]

        case .audioMP3:
            args += ["-f", plan.selector]
            args += ["-x", "--audio-format", "mp3", "--audio-quality", "320K"]
            args += ["--embed-thumbnail", "--add-metadata"]

        case .cover:
            args = []                                   // обложку качаем сами, без yt-dlp
        }

        if !args.isEmpty { args.append(url) }
        return args
    }

    /// Обновление самого yt-dlp (работает только для отдельно стоящего бинарника).
    public static func selfUpdate() -> [String] { ["-U"] }
}

/// Формирование имени файла по шаблону из настроек.
public enum FileNaming {

    /// Поддерживаются подстановки {title}, {quality}, {source}, {id}, {date}.
    public static func build(template: String, title: String, quality: String,
                             source: String, id: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var name = template
        for (key, value) in [
            "{title}": title,
            "{quality}": quality,
            "{source}": source,
            "{id}": id,
            "{date}": formatter.string(from: date),
        ] {
            name = name.replacingOccurrences(of: key, with: value)
        }
        // Схлопываем пустые скобки, оставшиеся от незаполненных подстановок.
        name = name.replacingOccurrences(of: "[]", with: "")
            .replacingOccurrences(of: "()", with: "")
        while name.contains("  ") { name = name.replacingOccurrences(of: "  ", with: " ") }
        return Fmt.safeFileName(name)
    }

    /// Подбирает свободное имя: «Ролик», «Ролик (2)», «Ролик (3)»…
    public static func uniqueBase(directory: URL, base: String, extensions: [String],
                                  exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
    -> String {
        var candidate = base
        var index = 2
        while extensions.contains(where: { exists(directory.appendingPathComponent("\(candidate).\($0)")) }) {
            candidate = "\(base) (\(index))"
            index += 1
            if index > 999 { break }
        }
        return candidate
    }
}
