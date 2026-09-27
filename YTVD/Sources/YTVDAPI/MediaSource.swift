import Foundation

/// Площадка, с которой качаем. Определяется по хосту ссылки.
public enum MediaSource: String, CaseIterable, Sendable {
    case youtube, vimeo, rutube, vk, other

    public var title: String {
        switch self {
        case .youtube: "YouTube"
        case .vimeo:   "Vimeo"
        case .rutube:  "Rutube"
        case .vk:      "VK Видео"
        case .other:   "Ссылка"
        }
    }

    /// Цвет метки площадки (RGB 0…1).
    public var accent: (r: Double, g: Double, b: Double) {
        switch self {
        case .youtube: (0.843, 0.294, 0.235)
        case .vimeo:   (0.231, 0.561, 0.820)
        case .rutube:  (0.545, 0.424, 0.780)
        case .vk:      (0.290, 0.498, 0.831)
        case .other:   (0.427, 0.478, 0.525)
        }
    }

    public var isSupported: Bool { self != .other }

    private static let hosts: [(suffix: String, source: MediaSource)] = [
        ("youtube.com", .youtube), ("youtu.be", .youtube), ("youtube-nocookie.com", .youtube),
        ("vimeo.com", .vimeo),
        ("rutube.ru", .rutube),
        ("vk.com", .vk), ("vk.ru", .vk), ("vkvideo.ru", .vk), ("vkvideo.ru", .vk), ("userapi.com", .vk),
    ]

    public static func detect(_ url: URL) -> MediaSource {
        guard var host = url.host?.lowercased() else { return .other }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        for (suffix, source) in hosts where host == suffix || host.hasSuffix("." + suffix) {
            return source
        }
        return .other
    }
}

/// Выцепляет первую поддерживаемую ссылку из произвольного текста (например, из буфера обмена).
public enum LinkDetector {

    public static func firstSupportedURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 4096 else { return nil }

        for token in trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "\u{200B}" }) {
            // Отрезаем обрамляющую пунктуацию: «(…watch?v=x).» → «…watch?v=x»
            var candidate = String(token)
            while let first = candidate.first, "([{<«\"'".contains(first) { candidate.removeFirst() }
            while let last = candidate.last, ")]}>»,.;!?\"'".contains(last) { candidate.removeLast() }
            guard let url = normalize(candidate), MediaSource.detect(url).isSupported else { continue }
            return url
        }
        return nil
    }

    /// Добавляет схему, если её нет, и отбрасывает всё, что не похоже на http(s)-ссылку.
    public static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            guard text.contains(".") , !text.hasPrefix("/") else { return nil }
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }
}
