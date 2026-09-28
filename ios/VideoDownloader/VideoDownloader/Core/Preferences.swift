import Foundation
import YTVDAPI

/// Ключи настроек в UserDefaults. Секретов здесь нет: токен лежит в Keychain.
enum Prefs {
    static let defaultQuality = "defaultQuality"
    static let wifiOnly = "wifiOnly"
    static let autoSaveToPhotos = "autoSaveToPhotos"
    static let keepOnMac = "keepOnMac"
    static let serverURL = "serverURL"
    static let serverName = "serverName"
    static let serverAlternates = "serverAlternates"

    static func register() {
        UserDefaults.standard.register(defaults: [
            defaultQuality: DefaultQuality.p1080.rawValue,
            wifiOnly: false,
            autoSaveToPhotos: false,
            keepOnMac: false,
        ])
    }

    static var wifiOnlyEnabled: Bool { UserDefaults.standard.bool(forKey: wifiOnly) }

    static var quality: DefaultQuality {
        DefaultQuality(rawValue: UserDefaults.standard.integer(forKey: defaultQuality)) ?? .p1080
    }
}

/// Качество, которое выбирается заранее: «Лучшее» или потолок по высоте кадра.
enum DefaultQuality: Int, CaseIterable, Identifiable {
    case best = 0
    case p2160 = 2160
    case p1440 = 1440
    case p1080 = 1080
    case p720 = 720

    var id: Int { rawValue }
    var title: String { self == .best ? "Лучшее" : "\(rawValue)p" }

    /// Самый высокий вариант не выше потолка. Если все выше — самый скромный из них.
    func pick(from formats: [VideoFormat]) -> VideoFormat? {
        let video = formats.filter(\.hasVideo)
        guard !video.isEmpty else { return formats.first }
        let rank: (VideoFormat) -> (Int, Int) = { ($0.classHeight, $0.fps ?? 0) }
        if self == .best { return video.max { rank($0) < rank($1) } }
        let fitting = video.filter { $0.classHeight <= rawValue }
        return fitting.max { rank($0) < rank($1) } ?? video.min { rank($0) < rank($1) }
    }
}

extension VideoFormat {

    /// Класс разрешения из подписи: «2160p60» → 2160. У вертикальных роликов это короткая сторона.
    var classHeight: Int {
        Int(label.prefix { $0.isNumber }) ?? height ?? 0
    }

    /// «4K · 2160p60», «1080p», «Только звук».
    var displayTitle: String {
        guard hasVideo else { return label }
        switch classHeight {
        case 4320...: return "8K · \(label)"
        case 2160...: return "4K · \(label)"
        default: return label
        }
    }

    /// «~1,8 ГБ», если размер прикинут по битрейту, и «483 МБ», если он точный.
    var sizeText: String? {
        guard let estimatedSize, estimatedSize > 0 else { return nil }
        return (sizeIsEstimated ? "~" : "") + Fmt.bytes(estimatedSize)
    }

    /// Кодек по-человечески — для «Подробностей».
    var codecTitle: String {
        switch codec.lowercased() {
        case "h264": "H.264"
        case "hevc", "h265": "HEVC"
        case "aac": "AAC"
        default: codec.uppercased()
        }
    }
}
