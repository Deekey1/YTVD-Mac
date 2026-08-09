import Foundation

/// Что именно скачиваем, если выбрать строку.
public struct DownloadPlan: Sendable, Equatable {
    public enum Mode: String, Sendable {
        case video          // видео + звук, при необходимости склейка через ffmpeg
        case audioNative    // звуковая дорожка как есть, без перекодирования
        case audioMP3       // перекодирование в MP3 320 с обложкой в тегах
        case cover          // только обложка JPEG
    }

    public var mode: Mode
    public var selector: String        // значение для `-f`
    public var container: String       // расширение итогового файла
    public var coverURL: String?

    public init(mode: Mode, selector: String, container: String, coverURL: String? = nil) {
        self.mode = mode; self.selector = selector; self.container = container; self.coverURL = coverURL
    }
}

/// Строка в списке вариантов.
public struct DownloadOption: Identifiable, Sendable, Equatable {
    public enum Group: String, Sendable, CaseIterable {
        case video, audio, cover

        public var title: String {
            switch self {
            case .video: "Видео"
            case .audio: "Аудио"
            case .cover: "Обложка"
            }
        }
    }

    /// Цветовая метка: смысл строки виден до чтения текста.
    public enum Tint: String, Sendable {
        case blue       // видео H.264 — играет везде
        case orange     // видео VP9/AV1 — легче, но капризнее
        case red        // звук
        case steel      // обложка
    }

    public let id: String
    public let group: Group
    public let tint: Tint
    public let title: String            // «1080p», «MP3», «JPEG»
    public let subtitle: String         // «Full HD», «320 кбит/с», «1280×720»
    public let bytes: Int64
    public let estimated: Bool          // размер прикинут по битрейту
    public let badge: String?           // «TG», «ТЕГИ»
    public let detail: String           // подробности под чевроном
    public let hint: String             // строка «что это значит»
    public let plan: DownloadPlan
    public let height: Int?             // разрешение — нужно для выбора по умолчанию

    /// Альтернативные кодеки прячем за строкой «ещё N».
    public var isAlternative: Bool { tint == .orange }

    public init(id: String, group: Group, tint: Tint, title: String, subtitle: String,
                bytes: Int64, estimated: Bool, badge: String?, detail: String, hint: String,
                plan: DownloadPlan, height: Int? = nil) {
        self.id = id; self.group = group; self.tint = tint; self.title = title
        self.subtitle = subtitle; self.bytes = bytes; self.estimated = estimated
        self.badge = badge; self.detail = detail; self.hint = hint; self.plan = plan
        self.height = height
    }

    /// Размер известен не всегда: Vimeo, например, не сообщает его для звуковых дорожек.
    public var hasKnownSize: Bool { bytes > 0 }

    public var sizeText: String {
        guard hasKnownSize else { return "—" }
        return (estimated ? "≈ " : "") + Fmt.bytes(bytes)
    }
}
