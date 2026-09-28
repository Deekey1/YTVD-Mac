import Foundation
import SwiftUI

/// Настройки приложения. Хранятся в UserDefaults, читаются мгновенно при запуске.
@MainActor
public final class AppSettings: ObservableObject {

    private enum Key {
        static let directory = "downloadDirectory"
        static let quality = "defaultQuality"
        static let alwaysH264 = "alwaysH264"
        static let watchClipboard = "watchClipboard"
        static let autoDownload = "autoDownload"
        static let saveCover = "saveCoverAlongside"
        static let floatOnTop = "floatOnTop"
        static let launchAtLogin = "launchAtLogin"
        static let template = "fileNameTemplate"
        static let limitSize = "limitFileSize"
        static let maxSizeMB = "maxFileSizeMB"
        static let appearance = "appearance"
        static let cookiesBrowser = "cookiesFromBrowser"
        static let proxy = "proxyURL"
        static let serverEnabled = "serverEnabled"
        static let serverPort = "serverPort"
        static let serverBind = "serverBind"
        static let serverKeepAwake = "serverKeepAwake"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.quality: 1080,
            Key.alwaysH264: true,
            Key.watchClipboard: true,
            Key.autoDownload: false,
            Key.saveCover: false,
            Key.floatOnTop: true,
            Key.launchAtLogin: false,
            Key.template: "{title} [{quality}]",
            Key.limitSize: false,
            Key.maxSizeMB: 50,
            Key.appearance: "system",
            Key.cookiesBrowser: "",
            Key.proxy: "",
            // Сервер для iPhone выключен, пока его не включат явно: Mac не должен
            // сам по себе становиться загрузчиком для всей домашней сети.
            Key.serverEnabled: false,
            Key.serverPort: Int(API.defaultPort),
            Key.serverBind: "all",
            Key.serverKeepAwake: true,
        ])
        self.directory = Self.readDirectory(defaults)
        self.defaultQuality = defaults.integer(forKey: Key.quality)
        self.alwaysH264 = defaults.bool(forKey: Key.alwaysH264)
        self.watchClipboard = defaults.bool(forKey: Key.watchClipboard)
        self.autoDownload = defaults.bool(forKey: Key.autoDownload)
        self.saveCoverAlongside = defaults.bool(forKey: Key.saveCover)
        self.floatOnTop = defaults.bool(forKey: Key.floatOnTop)
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        self.fileNameTemplate = defaults.string(forKey: Key.template) ?? "{title} [{quality}]"
        self.limitFileSize = defaults.bool(forKey: Key.limitSize)
        self.maxFileSizeMB = defaults.integer(forKey: Key.maxSizeMB)
        self.appearance = defaults.string(forKey: Key.appearance) ?? "system"
        self.cookiesFromBrowser = defaults.string(forKey: Key.cookiesBrowser) ?? ""
        self.proxyURL = defaults.string(forKey: Key.proxy) ?? ""
        self.serverEnabled = defaults.bool(forKey: Key.serverEnabled)
        self.serverPort = defaults.integer(forKey: Key.serverPort)
        self.serverBind = defaults.string(forKey: Key.serverBind) ?? "all"
        self.serverKeepAwake = defaults.bool(forKey: Key.serverKeepAwake)
    }

    @Published public var directory: URL { didSet { defaults.set(directory.path, forKey: Key.directory) } }
    @Published public var defaultQuality: Int { didSet { defaults.set(defaultQuality, forKey: Key.quality) } }
    @Published public var alwaysH264: Bool { didSet { defaults.set(alwaysH264, forKey: Key.alwaysH264) } }
    @Published public var watchClipboard: Bool { didSet { defaults.set(watchClipboard, forKey: Key.watchClipboard) } }
    @Published public var autoDownload: Bool { didSet { defaults.set(autoDownload, forKey: Key.autoDownload) } }
    @Published public var saveCoverAlongside: Bool { didSet { defaults.set(saveCoverAlongside, forKey: Key.saveCover) } }
    @Published public var floatOnTop: Bool { didSet { defaults.set(floatOnTop, forKey: Key.floatOnTop) } }
    @Published public var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    @Published public var fileNameTemplate: String { didSet { defaults.set(fileNameTemplate, forKey: Key.template) } }
    @Published public var limitFileSize: Bool { didSet { defaults.set(limitFileSize, forKey: Key.limitSize) } }
    @Published public var maxFileSizeMB: Int { didSet { defaults.set(maxFileSizeMB, forKey: Key.maxSizeMB) } }
    /// «system», «light» или «dark».
    @Published public var appearance: String { didSet { defaults.set(appearance, forKey: Key.appearance) } }
    /// Пусто — не использовать. Иначе safari, chrome, firefox…
    @Published public var cookiesFromBrowser: String { didSet { defaults.set(cookiesFromBrowser, forKey: Key.cookiesBrowser) } }
    @Published public var proxyURL: String { didSet { defaults.set(proxyURL, forKey: Key.proxy) } }
    /// Сервер для iPhone. Порт и адрес меняются через `defaults write studio.dk.ytvd serverPort 8765`.
    @Published public var serverEnabled: Bool { didSet { defaults.set(serverEnabled, forKey: Key.serverEnabled) } }
    @Published public var serverPort: Int { didSet { defaults.set(serverPort, forKey: Key.serverPort) } }
    /// «all» — домашняя сеть, «loopback» — только этот Mac, или конкретный адрес.
    @Published public var serverBind: String { didSet { defaults.set(serverBind, forKey: Key.serverBind) } }
    /// Не давать Mac засыпать, пока сервер включён: спящий Mac iPhone издалека не разбудит.
    @Published public var serverKeepAwake: Bool { didSet { defaults.set(serverKeepAwake, forKey: Key.serverKeepAwake) } }

    public var network: NetworkOptions {
        NetworkOptions(cookiesFromBrowser: cookiesFromBrowser,
                       proxy: proxyURL.trimmingCharacters(in: .whitespaces))
    }

    /// Короткое имя папки для кнопки в подвале.
    public var directoryLabel: String { directory.lastPathComponent }

    public var directoryDisplayPath: String {
        directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Сетевые настройки без создания объекта — нужны служебным режимам из терминала.
    nonisolated public static func storedNetwork(defaults: UserDefaults = .standard) -> NetworkOptions {
        NetworkOptions(cookiesFromBrowser: defaults.string(forKey: Key.cookiesBrowser),
                       proxy: defaults.string(forKey: Key.proxy))
    }

    public static func defaultDirectory() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        return movies.appendingPathComponent("YTVD", isDirectory: true)
    }

    private static func readDirectory(_ defaults: UserDefaults) -> URL {
        if let path = defaults.string(forKey: Key.directory), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultDirectory()
    }

    public func reset() {
        directory = Self.defaultDirectory()
        defaultQuality = 1080
        alwaysH264 = true
        watchClipboard = true
        autoDownload = false
        saveCoverAlongside = false
        floatOnTop = true
        fileNameTemplate = "{title} [{quality}]"
        limitFileSize = false
        maxFileSizeMB = 50
        appearance = "system"
        cookiesFromBrowser = ""
        proxyURL = ""
        // Сервер для iPhone сброс не трогает: иначе сопряжённый iPhone внезапно потеряет Mac.
    }
}
