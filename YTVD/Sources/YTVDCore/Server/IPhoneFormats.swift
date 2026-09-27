import Foundation

/// Как перекодировать, если исходник на iPhone не проигрывается.
public struct TranscodeSpec: Sendable, Equatable {
    /// Кодировщик ffmpeg. Аппаратный — на Apple Silicon быстрее реального времени.
    public var encoder: String
    /// Целевой битрейт видео, бит/с.
    public var bitrate: Int

    public init(encoder: String = "hevc_videotoolbox", bitrate: Int) {
        self.encoder = encoder; self.bitrate = bitrate
    }
}

/// Вариант для iPhone: что показать пользователю и как это получить.
public struct FormatChoice: Sendable, Equatable {
    public var format: VideoFormat
    public var plan: DownloadPlan
    /// Есть — значит после скачивания нужно перекодировать в HEVC.
    public var transcode: TranscodeSpec?
    /// Расширение итогового файла.
    public var finalExtension: String
}

/// Нормализация форматов под iPhone.
///
/// AVPlayer играет H.264 и HEVC, но не VP9; AV1 — только на A17 Pro и новее.
/// YouTube же выше 1080p отдаёт исключительно VP9 и AV1. Поэтому:
/// * до 1080p — H.264 со звуком AAC, без перекодирования, только склейка;
/// * выше — перекодирование на Mac в HEVC аппаратным кодировщиком.
/// Пользователь видит одну строку на разрешение, без кодеков и контейнеров.
public enum IPhoneFormats {

    /// Идентификатор варианта «только звук».
    public static let audioId = "audio"

    /// Разрешения, которые показываем. 240p — только если выше ничего нет.
    public static let standardHeights = [2160, 1440, 1080, 720, 480, 360, 240]

    public static func build(from info: MediaInfo, canMerge: Bool,
                             canTranscode: Bool) -> [FormatChoice] {
        let formats = info.formats ?? []
        let duration = info.duration

        let audioOnly = formats.filter { $0.hasAudio && !$0.hasVideo }
        let videoOnly = formats.filter { $0.hasVideo && !$0.hasAudio && isSDR($0) }
        let combined = formats.filter { $0.hasVideo && $0.hasAudio && isSDR($0) }

        // Звук для склейки: стерео AAC — его без перекодирования берёт контейнер MP4.
        let stereo = audioOnly.filter { ($0.audio_channels ?? 2) <= 2 }
        let pool = stereo.isEmpty ? audioOnly : stereo
        let aac = best(pool.filter { ($0.acodec ?? "").lowercased().hasPrefix("mp4a") })
        let audioBytes = aac?.bytes(duration: duration).value ?? 0

        var choices: [FormatChoice] = []

        for height in standardHeights {
            let bucket = { (format: RawFormat) in resolutionClass(format) == height }

            // 1. H.264 отдельной дорожкой + AAC: только склейка, качество исходное.
            if canMerge, let aac, let video = best(videoOnly.filter { bucket($0) && $0.videoFamily == .avc }) {
                choices.append(copyChoice(video: video, audio: aac, audioBytes: audioBytes,
                                          height: height, duration: duration))
                continue
            }
            // 2. Готовый файл со звуком в H.264 (так отдают Rutube, VK, часть Vimeo).
            if let file = best(combined.filter { bucket($0) && $0.videoFamily == .avc }) {
                choices.append(combinedChoice(file, height: height, duration: duration))
                continue
            }
            // 3. HEVC отдельной дорожкой — iPhone его играет, перекодировать не надо.
            if canMerge, let aac, let video = best(videoOnly.filter { bucket($0) && $0.videoFamily == .hevc }) {
                choices.append(copyChoice(video: video, audio: aac, audioBytes: audioBytes,
                                          height: height, duration: duration, codec: "hevc"))
                continue
            }
            // 4. Только VP9 или AV1 — перекодируем в HEVC на Mac.
            if canMerge, canTranscode, let aac,
               let video = best(videoOnly.filter {
                   bucket($0) && ($0.videoFamily == .vp9 || $0.videoFamily == .av1)
               }) {
                choices.append(transcodeChoice(video: video, audio: aac, audioBytes: audioBytes,
                                               height: height, duration: duration))
            }
        }

        // 240p — только если ничего приличнее нет.
        if choices.contains(where: { ($0.format.height ?? 0) >= 360 }) {
            choices.removeAll { ($0.format.height ?? 0) < 360 }
        }

        // Только звук: оригинальная дорожка, без перекодирования.
        if let audio = aac ?? best(pool) {
            choices.append(audioChoice(audio, duration: duration))
        }
        return choices
    }

    /// Что предложить по умолчанию: ближайшее к желаемому без перекодирования.
    public static func recommended(_ choices: [FormatChoice], preferredHeight: Int = 1080) -> String? {
        let video = choices.filter { $0.format.hasVideo }
        let fast = video.filter { !$0.format.needsTranscode }
        let pool = fast.isEmpty ? video : fast
        let notAbove = pool.filter { ($0.format.height ?? 0) <= preferredHeight }
        return (notAbove.max { ($0.format.height ?? 0) < ($1.format.height ?? 0) }
                ?? pool.min { ($0.format.height ?? 0) < ($1.format.height ?? 0) })?.format.id
    }

    // MARK: - определение разрешения

    /// Класс качества: у YouTube он записан в format_note («1080p60»), иначе берём
    /// короткую сторону кадра — вертикальное видео 1080×1920 это 1080p, а не 1920p.
    static func resolutionClass(_ format: RawFormat) -> Int? {
        if let note = format.format_note,
           let match = note.range(of: #"(\d{3,4})p"#, options: .regularExpression) {
            let digits = note[match].dropLast()
            if let value = Int(digits) { return snap(value) }
        }
        let side: Int?
        if let width = format.width, let height = format.height {
            side = min(width, height)
        } else {
            side = format.height
        }
        return side.flatMap(snap)
    }

    /// Прижимает нестандартную высоту к ближайшей стандартной снизу: 1072 → 1080, 800 → 720.
    static func snap(_ value: Int) -> Int? {
        standardHeights.first { Double(value) >= Double($0) * 0.93 }
    }

    private static func isSDR(_ format: RawFormat) -> Bool {
        let range = (format.dynamic_range ?? "SDR").uppercased()
        return range == "SDR" || range.isEmpty
    }

    /// Из нескольких вариантов одного разрешения — больше кадров, потом выше битрейт.
    private static func best(_ formats: [RawFormat]) -> RawFormat? {
        formats.enumerated().max { left, right in
            let l = (Int((left.element.fps ?? 0).rounded()), left.element.tbr ?? left.element.abr ?? 0,
                     left.offset)
            let r = (Int((right.element.fps ?? 0).rounded()), right.element.tbr ?? right.element.abr ?? 0,
                     right.offset)
            return l < r
        }?.element
    }

    // MARK: - сборка вариантов

    private static func label(height: Int, fps: Int?) -> String {
        guard let fps, fps >= 50 else { return "\(height)p" }
        return "\(height)p\(fps)"
    }

    private static func id(height: Int, fps: Int?) -> String {
        guard let fps, fps >= 50 else { return "h\(height)" }
        return "h\(height)-\(fps)"
    }

    private static func fps(_ format: RawFormat) -> Int? {
        format.fps.map { Int($0.rounded()) }
    }

    private static func copyChoice(video: RawFormat, audio: RawFormat, audioBytes: Int64,
                                   height: Int, duration: Double?, codec: String = "h264") -> FormatChoice {
        let (videoBytes, estimated) = video.bytes(duration: duration)
        let frames = fps(video)
        let selector = "\(video.format_id ?? "bv")+\(audio.format_id ?? "ba")"
            + "/bestvideo[height<=\(height)][vcodec^=avc1]+bestaudio[acodec^=mp4a]/best[height<=\(height)]"
        let format = VideoFormat(
            id: id(height: height, fps: frames), label: label(height: height, fps: frames),
            width: video.width, height: height, fps: frames, codec: codec, container: "mp4",
            hasVideo: true, hasAudio: true,
            estimatedSize: videoBytes + audioBytes > 0 ? videoBytes + audioBytes : nil,
            sizeIsEstimated: estimated || audio.knownBytes == nil, needsTranscode: false,
            details: "\(codec.uppercased()) + AAC, склейка без перекодирования · "
                + "\(video.format_id ?? "?")+\(audio.format_id ?? "?")")
        return FormatChoice(format: format,
                            plan: DownloadPlan(mode: .video, selector: selector, container: "mp4"),
                            transcode: nil, finalExtension: "mp4")
    }

    private static func combinedChoice(_ file: RawFormat, height: Int, duration: Double?) -> FormatChoice {
        let (bytes, estimated) = file.bytes(duration: duration)
        let frames = fps(file)
        let format = VideoFormat(
            id: id(height: height, fps: frames), label: label(height: height, fps: frames),
            width: file.width, height: height, fps: frames, codec: "h264",
            container: file.ext ?? "mp4", hasVideo: true, hasAudio: true,
            estimatedSize: bytes > 0 ? bytes : nil, sizeIsEstimated: estimated,
            needsTranscode: false,
            details: "Готовый файл со звуком · \(file.format_id ?? "?")")
        let selector = "\(file.format_id ?? "best")/best[height<=\(height)]"
        return FormatChoice(format: format,
                            plan: DownloadPlan(mode: .video, selector: selector, container: "mp4"),
                            transcode: nil, finalExtension: "mp4")
    }

    /// Битрейт HEVC по разрешению: с запасом, чтобы перекодированное не выглядело хуже исходника.
    static func hevcBitrate(height: Int, fps: Int?) -> Int {
        let base: Int
        switch height {
        case 2160...: base = 20_000_000
        case 1440...: base = 10_000_000
        case 1080...: base = 6_000_000
        default: base = 3_000_000
        }
        return (fps ?? 30) >= 50 ? base * 3 / 2 : base
    }

    private static func transcodeChoice(video: RawFormat, audio: RawFormat, audioBytes: Int64,
                                        height: Int, duration: Double?) -> FormatChoice {
        let frames = fps(video)
        let bitrate = hevcBitrate(height: height, fps: frames)
        let size = duration.map { Int64(Double(bitrate) / 8 * $0) + audioBytes }
        let source = video.videoFamily == .av1 ? "AV1" : "VP9"
        let format = VideoFormat(
            id: id(height: height, fps: frames), label: label(height: height, fps: frames),
            width: video.width, height: height, fps: frames, codec: "hevc", container: "mp4",
            hasVideo: true, hasAudio: true, estimatedSize: size, sizeIsEstimated: true,
            needsTranscode: true,
            details: "Исходник \(source) — iPhone его не играет, Mac перекодирует в HEVC "
                + "аппаратно · \(video.format_id ?? "?")+\(audio.format_id ?? "?")")
        let selector = "\(video.format_id ?? "bv")+\(audio.format_id ?? "ba")"
        return FormatChoice(format: format,
                            plan: DownloadPlan(mode: .video, selector: selector, container: "mkv"),
                            transcode: TranscodeSpec(bitrate: bitrate), finalExtension: "mp4")
    }

    private static func audioChoice(_ audio: RawFormat, duration: Double?) -> FormatChoice {
        let (bytes, estimated) = audio.bytes(duration: duration)
        let ext = audio.ext == "mp4" ? "m4a" : (audio.ext ?? "m4a")
        let format = VideoFormat(
            id: audioId, label: "Только звук", codec: "aac", container: ext,
            hasVideo: false, hasAudio: true, estimatedSize: bytes > 0 ? bytes : nil,
            sizeIsEstimated: estimated, needsTranscode: false,
            details: "Оригинальная дорожка без перекодирования · \(audio.format_id ?? "?")")
        return FormatChoice(format: format,
                            plan: DownloadPlan(mode: .audioNative, selector: audio.format_id ?? "bestaudio",
                                               container: ext),
                            transcode: nil, finalExtension: ext)
    }
}
