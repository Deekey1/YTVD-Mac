import Foundation

/// Обновление движка. Площадки ломают yt-dlp регулярно, поэтому приложение умеет
/// подтянуть свежую версию — но лезет в сеть только когда что-то уже пошло не так.
public enum EngineUpdater {

    public struct Available: Equatable, Sendable {
        public let current: String?
        public let latest: String
    }

    /// Куда кладём скачанное. Этот каталог приложение просматривает раньше системных.
    public static var directory: URL { BinaryLocator.managedDirectory }

    // MARK: - когда вообще стоит проверять

    private static let checkKey = "lastEngineCheck"
    private static let checkInterval: TimeInterval = 6 * 3600

    /// Не чаще раза в несколько часов: сбой может повторяться подряд, дёргать сеть незачем.
    public static func shouldCheck(now: Date = Date(),
                                   defaults: UserDefaults = .standard) -> Bool {
        let last = defaults.object(forKey: checkKey) as? Date
        guard let last else { return true }
        return now.timeIntervalSince(last) > checkInterval
    }

    public static func rememberCheck(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: checkKey)
    }

    // MARK: - сравнение версий

    /// Версии yt-dlp — даты вида 2026.07.04, иногда с четвёртым числом.
    public static func isNewer(_ candidate: String, than current: String?) -> Bool {
        guard let current, !current.isEmpty else { return true }
        let left = parts(candidate), right = parts(current)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    // MARK: - что есть на сервере

    /// Последний выпуск yt-dlp по данным GitHub.
    public static func latestYtDlpVersion() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        struct Release: Decodable { let tag_name: String }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.tag_name.isEmpty else {
            throw YTVDError.network("Не удалось узнать версию движка")
        }
        return release.tag_name
    }

    /// Проверяет, вышло ли обновление. Возвращает nil, если всё свежее или проверять рано.
    public static func check(current: String?, force: Bool = false,
                             defaults: UserDefaults = .standard) async -> Available? {
        guard force || shouldCheck(defaults: defaults) else { return nil }
        rememberCheck(defaults: defaults)

        guard let latest = try? await latestYtDlpVersion() else { return nil }
        guard isNewer(latest, than: current) else { return nil }
        return Available(current: current, latest: latest)
    }

    // MARK: - установка

    /// Распакованная сборка yt-dlp (onedir). Однофайловая при каждом запуске распаковывает
    /// Python во временную папку, и macOS заново проверяет его библиотеки — 6–8 секунд
    /// на любой вызов. Распакованную macOS проверяет один раз, дальше — доли секунды.
    public static let ytdlpURL = URL(
        string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip")!

    /// Исполняемый файл в сборке и начало имени её папки: во встроенной — yt-dlp_macos,
    /// у скачанных — yt-dlp_macos-<версия>. bin/yt-dlp — ссылка на исполняемый файл.
    static let ytdlpFolder = "yt-dlp_macos"

    /// Ставит свежий yt-dlp рядом с настройками приложения.
    @discardableResult
    public static func installYtDlp(onProgress: @escaping @Sendable (Double) -> Void = { _ in })
    async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (temporary, response) = try await URLSession.shared.download(from: ytdlpURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw YTVDError.network("Сервер вернул код \(http.statusCode)")
        }
        onProgress(0.7)

        let unpacked = directory.appendingPathComponent("unpack-yt-dlp")
        try? FileManager.default.removeItem(at: unpacked)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unpacked) }
        let archive = unpacked.appendingPathComponent("\(ytdlpFolder).zip")
        try FileManager.default.moveItem(at: temporary, to: archive)
        let bundle = unpacked.appendingPathComponent(ytdlpFolder)
        try await runDitto(archive: archive, into: bundle)
        onProgress(0.85)

        let installed = try await activateYtDlp(bundle, in: directory)
        onProgress(1)
        return installed
    }

    /// Ставит распакованную сборку на место: убеждается, что она запускается, кладёт её
    /// в свою папку yt-dlp_macos-<версия> и направляет на неё ссылку bin/yt-dlp — её и
    /// находит BinaryLocator. Однофайловый yt-dlp на месте ссылки заменяется ею.
    ///
    /// Прежнюю сборку не удаляем до следующего обновления: ею может ещё качать начатое
    /// задание, а распакованный yt-dlp подгружает свои части из папки по ходу работы.
    static func activateYtDlp(_ bundle: URL, in directory: URL) async throws -> URL {
        let files = FileManager.default
        let executable = bundle.appendingPathComponent(ytdlpFolder)
        guard files.isExecutableFile(atPath: executable.path) else {
            throw YTVDError.network("В архиве нет \(ytdlpFolder)")
        }
        // Первый запуск заодно даёт macOS проверить библиотеки: дальше yt-dlp стартует быстро.
        let check = try await ProcessRunner.run(executable, ["--version"])
        guard check.succeeded else { throw YTVDError.network("Скачанный yt-dlp не запускается") }

        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let version = check.stdout.filter { $0.isNumber || $0 == "." }
        var folder = "\(ytdlpFolder)-\(version.isEmpty ? "new" : version)"
        if files.fileExists(atPath: directory.appendingPathComponent(folder).path) {
            folder += "-\(UUID().uuidString.prefix(8))"
        }
        try files.moveItem(at: bundle, to: directory.appendingPathComponent(folder))

        // Новую ссылку кладём рядом и переименовываем поверх старой: rename(2) атомарен,
        // и bin/yt-dlp не пропадает ни на миг.
        let link = directory.appendingPathComponent("yt-dlp")
        let previous = (try? files.destinationOfSymbolicLink(atPath: link.path))?
            .split(separator: "/").first.map(String.init)
        let staged = directory.appendingPathComponent(".yt-dlp-\(UUID().uuidString)")
        try files.createSymbolicLink(atPath: staged.path, withDestinationPath: "\(folder)/\(ytdlpFolder)")
        guard rename(staged.path, link.path) == 0 else {
            try? files.removeItem(at: staged)
            throw YTVDError.network("Не удалось поставить yt-dlp на место")
        }

        // Держим только новую и предыдущую сборки.
        let keep = Set([folder, previous].compactMap { $0 })
        for name in (try? files.contentsOfDirectory(atPath: directory.path)) ?? []
        where name.hasPrefix(ytdlpFolder) && !keep.contains(name) {
            try? files.removeItem(at: directory.appendingPathComponent(name))
        }
        return link
    }

    /// Статическая сборка ffmpeg под текущую архитектуру.
    public static var ffmpegURL: URL {
        #if arch(arm64)
        URL(string: "https://www.osxexperts.net/ffmpeg81arm.zip")!
        #else
        URL(string: "https://evermeet.cx/ffmpeg/getrelease/zip")!
        #endif
    }

    @discardableResult
    public static func installFfmpeg(onProgress: @escaping @Sendable (Double) -> Void = { _ in })
    async throws -> URL {
        try await install(from: ffmpegURL, name: "ffmpeg", unzip: true, onProgress: onProgress)
    }

    private static func install(from url: URL, name: String, unzip: Bool = false,
                                onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)

        let (temporary, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw YTVDError.network("Сервер вернул код \(http.statusCode)")
        }
        onProgress(0.8)

        let payload: URL
        if unzip {
            let unpacked = directory.appendingPathComponent("unpack-\(name)")
            try? FileManager.default.removeItem(at: unpacked)
            try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)

            let archive = unpacked.appendingPathComponent("archive.zip")
            try FileManager.default.moveItem(at: temporary, to: archive)
            try await runUnzip(archive: archive, into: unpacked)

            guard let found = FileManager.default.enumerator(at: unpacked, includingPropertiesForKeys: nil)?
                .compactMap({ $0 as? URL })
                .first(where: { $0.lastPathComponent == name }) else {
                throw YTVDError.network("В архиве нет \(name)")
            }
            payload = found
        } else {
            payload = temporary
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: payload, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("unpack-\(name)"))
        onProgress(1)

        // Убеждаемся, что скачанное действительно запускается.
        let check = try await ProcessRunner.run(destination, name == "ffmpeg" ? ["-version"] : ["--version"])
        guard check.succeeded else {
            try? FileManager.default.removeItem(at: destination)
            throw YTVDError.network("Скачанный \(name) не запускается")
        }
        return destination
    }

    private static func runUnzip(archive: URL, into directory: URL) async throws {
        let result = try await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/unzip"),
            ["-qo", archive.path, "-d", directory.path])
        guard result.succeeded else { throw YTVDError.network("Не удалось распаковать архив") }
    }

    /// ditto, а не unzip: в сборке yt-dlp есть ссылки внутри Python.framework.
    private static func runDitto(archive: URL, into directory: URL) async throws {
        let result = try await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, directory.path])
        guard result.succeeded else { throw YTVDError.network("Не удалось распаковать архив") }
    }
}
