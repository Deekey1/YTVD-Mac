import Foundation

/// Ссылки из «Поделиться»: расширение кладёт их в общий контейнер App Group,
/// приложение забирает при следующем открытии. Расширение само ничего не скачивает.
enum SharedInbox {

    /// Идентификатор группы берём из Info.plist — он собирается из префикса в Signing.xcconfig.
    static var groupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
    }

    /// Общий UserDefaults, если App Group действительно подключена подписью.
    private static var defaults: UserDefaults? {
        guard let group = groupIdentifier,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else {
            return nil
        }
        return UserDefaults(suiteName: group)
    }

    private static let key = "pendingLinks"

    /// Кладёт ссылку в ящик. false — общего контейнера нет, передать можно только через открытие приложения.
    @discardableResult
    static func push(_ url: URL) -> Bool {
        guard let defaults else { return false }
        var list = defaults.stringArray(forKey: key) ?? []
        list.removeAll { $0 == url.absoluteString }
        list.append(url.absoluteString)
        defaults.set(Array(list.suffix(20)), forKey: key)
        return true
    }

    /// Забирает все ссылки и очищает ящик.
    static func popAll() -> [URL] {
        guard let defaults else { return [] }
        let list = defaults.stringArray(forKey: key) ?? []
        guard !list.isEmpty else { return [] }
        defaults.removeObject(forKey: key)
        return list.compactMap(URL.init(string:))
    }

    // MARK: - ссылка на приложение

    static let scheme = "videodownloader"

    /// videodownloader://add?url=… — так расширение открывает приложение сразу со ссылкой.
    static func deepLink(for url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "add"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url
    }

    static func link(fromDeepLink url: URL) -> URL? {
        guard url.scheme == scheme,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value else { return nil }
        return URL(string: value)
    }

    /// Первая http(s)-ссылка в произвольном тексте: YouTube делится «Название https://youtu.be/…».
    static func firstWebURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .first { $0.scheme == "http" || $0.scheme == "https" }
    }
}
