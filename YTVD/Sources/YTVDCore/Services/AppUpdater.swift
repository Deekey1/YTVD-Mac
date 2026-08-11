import AppKit
import Foundation

/// Обновление самой программы: смотрит выпуски на GitHub и умеет поставить новый образ.
public enum AppUpdater {

    public struct Available: Equatable, Sendable {
        public let version: String
        public let dmgURL: URL
        public let pageURL: URL
    }

    public static let repository = "Deekey1/YTVD-Mac"

    /// Версия из Info.plist собранного приложения.
    public static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - проверка

    public static func check(current: String = currentVersion) async throws -> Available? {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Закрытый репозиторий отвечает 404 всем, кто не авторизован, — а приложение
        // авторизоваться не может и не должно. Говорим об этом прямо.
        if let http = response as? HTTPURLResponse, http.statusCode == 404 || http.statusCode == 403 {
            throw YTVDError.network("Репозиторий закрыт — проверка обновлений через него "
                                  + "недоступна. Сделайте его публичным на GitHub.")
        }

        struct Asset: Decodable { let name: String; let browser_download_url: String }
        struct Release: Decodable {
            let tag_name: String
            let html_url: String
            let assets: [Asset]
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
            throw YTVDError.network("Не удалось прочитать список выпусков")
        }

        let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard EngineUpdater.isNewer(latest, than: current) else { return nil }

        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let dmg = URL(string: asset.browser_download_url),
              let page = URL(string: release.html_url) else {
            throw YTVDError.network("В выпуске \(latest) нет образа для установки")
        }
        return Available(version: latest, dmgURL: dmg, pageURL: page)
    }

    // MARK: - установка

    /// Качает образ, достаёт из него приложение и подменяет установленное,
    /// после чего перезапускается. Подмена идёт из отдельного скрипта: заменить
    /// самого себя, пока работаешь, нельзя.
    public static func install(_ update: Available,
                               onProgress: @escaping @Sendable (String) -> Void) async throws {
        onProgress("Скачиваю \(update.version)…")
        let (temporary, response) = try await URLSession.shared.download(from: update.dmgURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw YTVDError.network("Сервер вернул код \(http.statusCode)")
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytvd-update-\(update.version)")
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let image = work.appendingPathComponent("YTVD.dmg")
        try FileManager.default.moveItem(at: temporary, to: image)

        onProgress("Распаковываю…")
        let mount = work.appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)

        let attach = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/hdiutil"),
            ["attach", image.path, "-nobrowse", "-readonly", "-mountpoint", mount.path])
        guard attach.succeeded else { throw YTVDError.network("Не удалось открыть образ") }

        defer {
            Task { _ = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/hdiutil"),
                                                    ["detach", mount.path, "-quiet"]) }
        }

        let source = mount.appendingPathComponent("YTVD.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw YTVDError.network("В образе нет YTVD.app")
        }

        let staged = work.appendingPathComponent("YTVD.app")
        let copy = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                               [source.path, staged.path])
        guard copy.succeeded else { throw YTVDError.network("Не удалось скопировать приложение") }

        onProgress("Подменяю и перезапускаю…")
        try await swapAndRelaunch(staged: staged, work: work)
    }

    /// Скрипт дожидается выхода приложения, подменяет бандл и запускает заново.
    private static func swapAndRelaunch(staged: URL, work: URL) async throws {
        let target = Bundle.main.bundleURL
        let script = work.appendingPathComponent("install.sh")
        let pid = ProcessInfo.processInfo.processIdentifier

        let body = """
        #!/bin/bash
        # Ждём, пока старое приложение закроется, иначе подмена его же файлов ненадёжна.
        for _ in $(seq 1 100); do
          kill -0 \(pid) 2>/dev/null || break
          sleep 0.1
        done
        rm -rf "\(target.path)"
        mv "\(staged.path)" "\(target.path)"
        xattr -dr com.apple.quarantine "\(target.path)" 2>/dev/null
        open -n "\(target.path)"
        rm -rf "\(work.path)"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: script.path)

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [script.path]
        try launcher.run()

        await MainActor.run { NSApp.terminate(nil) }
    }
}
