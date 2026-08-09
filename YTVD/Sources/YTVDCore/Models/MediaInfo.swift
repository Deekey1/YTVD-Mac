import Foundation

/// Один формат из выдачи `yt-dlp -J`. Все поля необязательные — площадки отдают разный набор.
public struct RawFormat: Decodable, Sendable, Equatable {
    public var format_id: String?
    public var ext: String?
    public var vcodec: String?
    public var acodec: String?
    public var height: Int?
    public var width: Int?
    public var fps: Double?
    public var filesize: Int64?
    public var filesize_approx: Int64?
    public var tbr: Double?                 // общий битрейт, кбит/с
    public var abr: Double?
    public var vbr: Double?
    public var format_note: String?
    public var audio_channels: Int?
    public var `protocol`: String?

    public init(format_id: String? = nil, ext: String? = nil, vcodec: String? = nil,
                acodec: String? = nil, height: Int? = nil, width: Int? = nil, fps: Double? = nil,
                filesize: Int64? = nil, filesize_approx: Int64? = nil, tbr: Double? = nil,
                abr: Double? = nil, vbr: Double? = nil, format_note: String? = nil,
                audio_channels: Int? = nil, protocol: String? = nil) {
        self.format_id = format_id; self.ext = ext; self.vcodec = vcodec; self.acodec = acodec
        self.height = height; self.width = width; self.fps = fps
        self.filesize = filesize; self.filesize_approx = filesize_approx
        self.tbr = tbr; self.abr = abr; self.vbr = vbr; self.format_note = format_note
        self.audio_channels = audio_channels; self.protocol = `protocol`
    }

    // Важно различать «кодек указан как none» (дорожки точно нет) и «кодек не указан»
    // (площадка просто не сообщила). Vimeo, например, отдаёт звуковые дорожки
    // с vcodec="none" и вообще без acodec — если считать это отсутствием звука,
    // видео скачается немым.

    public var hasVideo: Bool {
        if let vcodec, !vcodec.isEmpty { return vcodec != "none" }
        // Кодек не назван: видео есть, если известно разрешение либо это цельный файл.
        return (height ?? 0) > 0 || acodec == nil
    }

    public var hasAudio: Bool {
        if let acodec, !acodec.isEmpty { return acodec != "none" }
        // Кодек не назван: звук есть у отдельной звуковой дорожки и у цельного файла,
        // но не у дорожки, про которую прямо сказано, что она только видео.
        return vcodec == nil || vcodec == "none"
    }

    /// Точный размер, если он известен.
    public var knownBytes: Int64? { filesize ?? filesize_approx }

    /// Размер: известный либо прикинутый по битрейту и длительности.
    public func bytes(duration: Double?) -> (value: Int64, estimated: Bool) {
        if let known = knownBytes, known > 0 { return (known, false) }
        if let duration, duration > 0, let rate = tbr ?? abr ?? vbr, rate > 0 {
            return (Int64(rate * 1000 / 8 * duration), true)
        }
        return (0, true)
    }

    /// Семейство видеокодека: avc1 / vp9 / av01 / прочее.
    public var videoFamily: VideoFamily {
        let c = (vcodec ?? "").lowercased()
        if c.hasPrefix("avc1") || c.hasPrefix("h264") { return .avc }
        if c.hasPrefix("vp9") || c.hasPrefix("vp09") { return .vp9 }
        if c.hasPrefix("av01") || c.hasPrefix("av1") { return .av1 }
        if c.hasPrefix("hev") || c.hasPrefix("hvc") { return .hevc }
        return .other
    }

    public enum VideoFamily: String, Sendable { case avc, vp9, av1, hevc, other }
}

public struct RawThumbnail: Decodable, Sendable, Equatable {
    public var url: String?
    public var width: Int?
    public var height: Int?
    public var preference: Int?

    public init(url: String? = nil, width: Int? = nil, height: Int? = nil, preference: Int? = nil) {
        self.url = url; self.width = width; self.height = height; self.preference = preference
    }
}

/// Разобранная выдача `yt-dlp -J` для одного ролика.
public struct MediaInfo: Decodable, Sendable, Equatable {
    public var id: String?
    public var title: String?
    public var uploader: String?
    public var channel: String?
    public var duration: Double?
    public var thumbnail: String?
    public var thumbnails: [RawThumbnail]?
    public var view_count: Int?
    public var upload_date: String?
    public var webpage_url: String?
    public var extractor_key: String?
    public var is_live: Bool?
    public var formats: [RawFormat]?

    public init(id: String? = nil, title: String? = nil, uploader: String? = nil,
                channel: String? = nil, duration: Double? = nil, thumbnail: String? = nil,
                thumbnails: [RawThumbnail]? = nil, view_count: Int? = nil,
                upload_date: String? = nil, webpage_url: String? = nil,
                extractor_key: String? = nil, is_live: Bool? = nil, formats: [RawFormat]? = nil) {
        self.id = id; self.title = title; self.uploader = uploader; self.channel = channel
        self.duration = duration; self.thumbnail = thumbnail; self.thumbnails = thumbnails
        self.view_count = view_count; self.upload_date = upload_date
        self.webpage_url = webpage_url; self.extractor_key = extractor_key
        self.is_live = is_live; self.formats = formats
    }

    public var displayTitle: String { (title?.isEmpty == false ? title! : nil) ?? "Без названия" }
    public var displayAuthor: String? { channel ?? uploader }

    /// Самая крупная доступная обложка.
    ///
    /// У YouTube лучшие картинки (maxresdefault) приходят без размеров, зато с большим
    /// `preference`, поэтому сортируем сначала по нему. При равенстве предпочитаем JPEG —
    /// его не надо перекодировать.
    public var bestThumbnail: RawThumbnail? {
        let list = (thumbnails ?? []).filter { $0.url?.isEmpty == false }
        guard !list.isEmpty else {
            return thumbnail.map { RawThumbnail(url: $0) }
        }

        let ranked = list.enumerated().sorted { left, right in
            let leftKey = (left.element.preference ?? Int.min, left.element.width ?? 0, left.offset)
            let rightKey = (right.element.preference ?? Int.min, right.element.width ?? 0, right.offset)
            return leftKey > rightKey
        }.map(\.element)

        let best = ranked[0]
        let isWebP: (RawThumbnail) -> Bool = { ($0.url ?? "").lowercased().contains(".webp") }
        guard isWebP(best) else { return best }

        // Ищем JPEG того же качества: preference отличается не больше чем на единицу.
        let sameQuality = ranked.prefix { ($0.preference ?? Int.min) >= (best.preference ?? Int.min) - 1 }
        return sameQuality.first(where: { !isWebP($0) }) ?? best
    }
}
