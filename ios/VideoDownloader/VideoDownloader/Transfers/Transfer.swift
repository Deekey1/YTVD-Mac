import Foundation
import YTVDAPI

/// Одна загрузка: сначала Mac качает ролик, потом iPhone забирает готовый файл.
struct Transfer: Codable, Identifiable, Equatable {

    enum Phase: String, Codable {
        /// Mac скачивает, склеивает или перекодирует.
        case mac
        /// Файл идёт на iPhone.
        case transfer
        case failed
    }

    var id: UUID
    var jobId: String
    /// Mac, на котором создано задание: файл забираем именно с него.
    var server: URL
    var video: VideoInfo
    var format: VideoFormat
    var phase: Phase = .mac
    /// Последнее, что сервер сообщил о задании.
    var job: JobInfo?
    var received: Int64 = 0
    var expected: Int64?
    /// Скорость передачи на iPhone, байт в секунду.
    var speed: Double?
    var error: String?
    /// «Заменить»: после загрузки удалить прежнюю копию ролика.
    var replaces: UUID?
    var attempts = 0
    var thumbnailName: String?
    var createdAt = Date()

    var isActive: Bool { phase == .mac || phase == .transfer }
    var thumbnailURL: URL? { thumbnailName.map { LibraryFiles.thumbnails.appendingPathComponent($0) } }
}

// MARK: - как показывать

extension Transfer {

    /// Что происходит сейчас — одной строкой.
    var stageTitle: String {
        switch phase {
        case .mac:
            guard let job else { return "Отправка на Mac…" }
            switch job.status {
            case .queued: return "В очереди на Mac"
            case .resolving: return "Mac готовит скачивание"
            case .downloadingVideo: return "Mac скачивает видео"
            case .downloadingAudio: return "Mac скачивает звук"
            case .merging: return "Объединение видео и аудио…"
            case .transcoding: return "Mac перекодирует для iPhone"
            case .ready: return "Передача на iPhone"
            case .failed, .cancelled, .interrupted: return job.status.title
            }
        case .transfer:
            return "Передача на iPhone"
        case .failed:
            return "Ошибка"
        }
    }

    /// Доля этапа 0…1. nil — этап без понятного прогресса: крутим индикатор, а не «висим на 100 %».
    var fraction: Double? {
        switch phase {
        case .mac:
            guard let job else { return nil }
            switch job.status {
            case .downloadingVideo, .downloadingAudio, .transcoding: return job.progress
            default: return nil
            }
        case .transfer:
            guard let expected, expected > 0 else { return nil }
            return min(1, Double(received) / Double(expected))
        case .failed:
            return nil
        }
    }

    /// «74 % · 356 МБ из 483 МБ · 12,4 МБ/с · ~11 с»
    var detailLine: String? {
        var parts: [String] = []
        switch phase {
        case .mac:
            guard let job else { return nil }
            if let fraction { parts.append(Fmt.percent(fraction)) }
            if job.status == .downloadingVideo || job.status == .downloadingAudio,
               let done = job.downloadedBytes, let total = job.totalBytes, total > 0 {
                parts.append("\(Fmt.bytes(done)) из \(Fmt.bytes(total))")
            }
            if let speed = job.speed, speed > 0 { parts.append(Fmt.speed(speed)) }
            if let eta = job.eta, eta > 0 { parts.append(Fmt.eta(eta)) }
        case .transfer:
            if let fraction { parts.append(Fmt.percent(fraction)) }
            if let expected {
                parts.append("\(Fmt.bytes(received)) из \(Fmt.bytes(expected))")
            } else if received > 0 {
                parts.append(Fmt.bytes(received))
            }
            if let speed, speed > 0 {
                parts.append(Fmt.speed(speed))
                if let expected, expected > received {
                    parts.append(Fmt.eta(Int((Double(expected - received) / speed).rounded(.up))))
                }
            }
        case .failed:
            return nil
        }
        return parts.isEmpty ? nil : parts.map(Self.unbreakable).joined(separator: " · ")
    }

    /// Строка переносится только между частями: «589 КБ/с» не должно разъезжаться на две строки.
    static func unbreakable(_ part: String) -> String {
        part.replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: "/", with: "/\u{2060}")
    }
}
