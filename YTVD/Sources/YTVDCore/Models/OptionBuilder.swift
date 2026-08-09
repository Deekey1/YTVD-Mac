import Foundation

/// Превращает сырую выдачу yt-dlp в понятный список вариантов.
///
/// Правила подбора:
/// * H.264 в MP4 — основной список: играет везде, годится для Telegram и iPhone;
/// * VP9/AV1 — только если реально легче того же разрешения (иначе смысла нет);
/// * звук — оригинальная дорожка без потерь качества плюс MP3 320 для совместимости;
/// * обложка — самая крупная из доступных.
public enum OptionBuilder {

    /// На сколько процентов альтернативный кодек должен быть легче, чтобы попасть в список.
    private static let altSavingThreshold = 0.12
    private static let maxAlternatives = 4
    private static let mp3Bitrate: Double = 320

    public static func build(from info: MediaInfo) -> [DownloadOption] {
        let formats = info.formats ?? []
        let duration = info.duration

        let audioOnly = formats.filter { $0.hasAudio && !$0.hasVideo }
        let videoOnly = formats.filter { $0.hasVideo && !$0.hasAudio }
        let combined  = formats.filter { $0.hasVideo && $0.hasAudio }

        // Многоканальные дорожки (5.1) весят втрое и не нужны для обычного просмотра —
        // берём стерео, если оно есть.
        let stereoOnly = audioOnly.filter { ($0.audio_channels ?? 2) <= 2 }
        let audioPool = stereoOnly.isEmpty ? audioOnly : stereoOnly

        let bestAAC = pickBestAudio(audioPool.filter {
            ($0.acodec ?? "").lowercased().hasPrefix("mp4a")
        })
        let bestAudio = pickBestAudio(audioPool)
        let audioForMux = bestAAC ?? bestAudio
        let audioBytes = audioForMux?.bytes(duration: duration).value ?? 0

        var result: [DownloadOption] = []

        // ── видео H.264 ───────────────────────────────────────────────────────
        let avcByHeight = bestPerHeight(videoOnly.filter { $0.videoFamily == .avc })
        var mainSizes: [Int: Int64] = [:]

        for (height, format) in avcByHeight.sorted(by: { $0.key > $1.key }) {
            let (videoBytes, estimated) = format.bytes(duration: duration)
            let total = videoBytes + audioBytes
            mainSizes[height] = total
            result.append(videoOption(
                format: format, height: height, tint: .blue,
                bytes: total, estimated: estimated || (audioForMux?.knownBytes == nil && audioBytes > 0),
                audio: audioForMux, container: "mp4", duration: duration))
        }

        // Если раздельных дорожек нет (частый случай у Rutube и VK) — берём готовые склейки.
        if avcByHeight.isEmpty {
            for (height, format) in bestPerHeight(combined).sorted(by: { $0.key > $1.key }) {
                let (bytes, estimated) = format.bytes(duration: duration)
                mainSizes[height] = bytes
                result.append(videoOption(
                    format: format, height: height, tint: .blue, bytes: bytes, estimated: estimated,
                    audio: nil, container: format.ext ?? "mp4", duration: duration))
            }
        }

        // ── видео VP9 / AV1: только когда заметно легче ───────────────────────
        let altFormats = videoOnly.filter { $0.videoFamily == .vp9 || $0.videoFamily == .av1 }
        var alternatives: [DownloadOption] = []
        for (height, format) in bestPerHeight(altFormats).sorted(by: { $0.key > $1.key }) {
            let (videoBytes, estimated) = format.bytes(duration: duration)
            let total = videoBytes + audioBytes
            if let reference = mainSizes[height] {
                guard reference > 0, Double(total) < Double(reference) * (1 - altSavingThreshold) else { continue }
            }
            alternatives.append(videoOption(
                format: format, height: height, tint: .orange, bytes: total, estimated: estimated,
                audio: audioForMux, container: format.videoFamily == .av1 ? "mp4" : "webm",
                duration: duration, savingVersus: mainSizes[height]))
        }
        result.append(contentsOf: alternatives.prefix(maxAlternatives))

        // ── звук ──────────────────────────────────────────────────────────────
        if let duration, duration > 0 {
            let mp3Bytes = Int64(mp3Bitrate * 1000 / 8 * duration)
            result.append(DownloadOption(
                id: "audio-mp3", group: .audio, tint: .red,
                title: "MP3", subtitle: "320 кбит/с",
                bytes: mp3Bytes, estimated: true, badge: "ТЕГИ",
                detail: "Перекодирование лучшей дорожки в MP3 320 кбит/с средствами ffmpeg, обложка в тегах",
                hint: "Откроется где угодно — от машины до колонки",
                plan: DownloadPlan(mode: .audioMP3,
                                   selector: bestAudio?.format_id ?? "bestaudio/best",
                                   container: "mp3")))
        }

        if let native = bestAudio, let id = native.format_id {
            let (bytes, estimated) = native.bytes(duration: duration)
            let codec = (native.acodec ?? "?").split(separator: ".").first.map(String.init) ?? "?"
            var ext = native.ext ?? "m4a"
            if ext == "mp4" { ext = "m4a" }              // звук в контейнере mp4 принято звать m4a
            result.append(DownloadOption(
                id: "audio-native-\(id)", group: .audio, tint: .red,
                title: ext.uppercased(), subtitle: "оригинал",
                bytes: bytes, estimated: estimated, badge: nil,
                detail: "\(codec) \(Int((native.abr ?? native.tbr ?? 0).rounded())) кбит/с · itag \(id) · без перекодирования",
                hint: "Быстро и без потери качества — звук копируется как есть",
                plan: DownloadPlan(mode: .audioNative, selector: id, container: ext)))
        }

        // ── обложка ───────────────────────────────────────────────────────────
        if let thumb = info.bestThumbnail, let url = thumb.url {
            let size = (thumb.width ?? 0) > 0 && (thumb.height ?? 0) > 0
                ? "\(thumb.width!)×\(thumb.height!)" : "исходный размер"
            result.append(DownloadOption(
                id: "cover", group: .cover, tint: .steel,
                title: "JPEG", subtitle: size,
                bytes: estimatedCoverBytes(thumb), estimated: true, badge: nil,
                detail: "JPEG · \(size) · сохраняется рядом с видео",
                hint: "Можно скачать отдельно, не трогая видео",
                plan: DownloadPlan(mode: .cover, selector: "", container: "jpg", coverURL: url)))
        }

        return result
    }

    // MARK: - вспомогательное

    /// Лучшая звуковая дорожка. Битрейт известен не всегда (Vimeo его не сообщает),
    /// поэтому при равенстве смотрим на пометку «high» в названии и на порядок:
    /// yt-dlp перечисляет форматы от худшего к лучшему.
    private static func pickBestAudio(_ formats: [RawFormat]) -> RawFormat? {
        func key(_ item: (offset: Int, element: RawFormat)) -> (Double, Int, Int) {
            let rate = item.element.abr ?? item.element.tbr ?? 0
            let named = (item.element.format_id ?? "").lowercased().contains("high") ? 1 : 0
            return (rate, named, item.offset)
        }
        return formats.enumerated().max { key($0) < key($1) }?.element
    }

    /// Для каждой высоты — самый качественный формат.
    private static func bestPerHeight(_ formats: [RawFormat]) -> [Int: RawFormat] {
        var best: [Int: RawFormat] = [:]
        for format in formats {
            guard let height = format.height, height > 0 else { continue }
            let score = format.tbr ?? format.vbr ?? 0
            if let existing = best[height], (existing.tbr ?? existing.vbr ?? 0) >= score { continue }
            best[height] = format
        }
        return best
    }

    private static func videoOption(format: RawFormat, height: Int, tint: DownloadOption.Tint,
                                    bytes: Int64, estimated: Bool, audio: RawFormat?,
                                    container: String, duration: Double?,
                                    savingVersus: Int64? = nil) -> DownloadOption {
        let id = format.format_id ?? "v\(height)"
        let selector: String
        if let audioID = audio?.format_id, !format.hasAudio {
            selector = "\(id)+\(audioID)"
        } else {
            selector = id
        }

        let family = format.videoFamily
        let subtitle: String
        switch (tint, family) {
        case (.orange, .av1): subtitle = "AV1"
        case (.orange, _):    subtitle = "VP9"
        default:              subtitle = resolutionClass(height)
        }

        let fps = format.fps.map { Int($0.rounded()) } ?? 30
        let rate = format.tbr ?? format.vbr
        let rateText = rate.map { " · \(Fmt.speedBits($0)) " } ?? " "
        let itag = audio?.format_id.map { "\(id)+\($0)" } ?? id
        let detail = "\(container.uppercased()) · \(format.vcodec ?? "?") · \(fps) к/с"
            + rateText + "· itag \(itag)"

        let hint: String
        switch (tint, family) {
        case (.blue, _) where height <= 1080:
            hint = "Играет везде: QuickTime, Telegram, iPhone"
        case (.blue, _):
            hint = "Играет везде, но файл тяжёлый"
        case (.orange, _):
            if let reference = savingVersus, reference > 0, bytes > 0 {
                let saving = Int(((Double(reference) - Double(bytes)) / Double(reference) * 100).rounded())
                hint = "Легче на \(saving) %, но QuickTime такой файл не откроет"
            } else {
                hint = "Легче по весу, но нужен современный плеер"
            }
        default:
            hint = ""
        }

        return DownloadOption(
            id: "video-\(id)", group: .video, tint: tint,
            title: "\(height)p" + (fps >= 50 ? "\(fps)" : ""),
            subtitle: subtitle,
            bytes: bytes, estimated: estimated,
            badge: tint == .blue && height <= 1080 && family == .avc ? "TG" : nil,
            detail: detail, hint: hint,
            plan: DownloadPlan(mode: .video, selector: selector, container: container),
            height: height)
    }

    private static func resolutionClass(_ height: Int) -> String {
        switch height {
        case 2160...: "4K"
        case 1440..<2160: "2K"
        case 1080..<1440: "Full HD"
        case 720..<1080: "HD"
        default: ""
        }
    }

    /// Обложку качаем сетевым запросом, точный размер заранее неизвестен — прикидываем по площади.
    private static func estimatedCoverBytes(_ thumb: RawThumbnail) -> Int64 {
        let pixels = Double((thumb.width ?? 1280) * (thumb.height ?? 720))
        return Int64(max(20_000, pixels * 0.1))
    }
}

extension Fmt {
    /// «4,1 Мбит/с» — для строки подробностей.
    static func speedBits(_ kbps: Double) -> String {
        kbps >= 1000
            ? String(format: "%.1f", kbps / 1000).replacingOccurrences(of: ".", with: ",") + " Мбит/с"
            : "\(Int(kbps.rounded())) кбит/с"
    }
}
