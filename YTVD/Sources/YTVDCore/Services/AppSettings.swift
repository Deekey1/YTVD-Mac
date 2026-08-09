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
        static let showHints = "showKeyboardHints"
        static let cookiesBrowser = "cookiesFromBrowser"
        static let proxy = "proxyURL"
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
            Key.showHints: true,
            Key.cookiesBrowser: "",
            Key.proxy: "",
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
        self.showKeyboardHints = defaults.bool(forKey: Key.showHints)
        self.cookiesFromBrowser = defaults.string(forKey: Key.cookiesBrowser) ?? ""
        self.proxyURL = defaults.string(forKey: Key.proxy) ?? ""
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
    @Published public var showKeyboardHints: Bool { didSet { defaults.set(showKeyboardHints, forKey: Key.showHints) } }
    /// Пусто — не использовать. Иначе safari, chrome, firefox…
    @Published public var cookiesFromBrowser: String { didSet { defaults.set(cookiesFromBrowser, forKey: Key.cookiesBrowser) } }
    @Published public var proxyURL: String { didSet { defaults.set(proxyURL, forKey: Key.proxy) } }

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
        showKeyboardHints = true
        cookiesFromBrowser = ""
        proxyURL = ""
    }
}
