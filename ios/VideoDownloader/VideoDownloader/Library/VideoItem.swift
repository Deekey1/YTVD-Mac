import Foundation
import SwiftData

/// Скачанное видео. Сам файл лежит в Videos/ под внутренним именем — здесь только сведения о нём.
@Model
final class VideoItem {
    @Attribute(.unique) var id: UUID
    /// Идентификатор ролика на площадке — по нему находятся дубликаты.
    var videoId: String
    var title: String
    var channel: String?
    var duration: Double?
    /// Настоящий размер кадра из файла: у вертикальных роликов высота больше ширины.
    var width: Int?
    var height: Int?
    var fps: Int?
    var formatLabel: String
    var codec: String
    var isAudioOnly: Bool
    var fileName: String
    var thumbnailName: String?
    var fileSize: Int64
    var sourceURL: String
    var platform: String
    var downloadedAt: Date
    /// «Избранное». Значение по умолчанию нужно SwiftData, чтобы дописать поле в прежнюю базу.
    var isFavorite: Bool = false

    init(id: UUID = UUID(), videoId: String, title: String, channel: String?, duration: Double?,
         width: Int?, height: Int?, fps: Int?, formatLabel: String, codec: String, isAudioOnly: Bool,
         fileName: String, thumbnailName: String?, fileSize: Int64, sourceURL: String,
         platform: String, downloadedAt: Date = Date(), isFavorite: Bool = false) {
        self.id = id
        self.videoId = videoId
        self.title = title
        self.channel = channel
        self.duration = duration
        self.width = width
        self.height = height
        self.fps = fps
        self.formatLabel = formatLabel
        self.codec = codec
        self.isAudioOnly = isAudioOnly
        self.fileName = fileName
        self.thumbnailName = thumbnailName
        self.fileSize = fileSize
        self.sourceURL = sourceURL
        self.platform = platform
        self.downloadedAt = downloadedAt
        self.isFavorite = isFavorite
    }

    var fileURL: URL { LibraryFiles.videos.appendingPathComponent(fileName) }
    var thumbnailURL: URL? { thumbnailName.map { LibraryFiles.thumbnails.appendingPathComponent($0) } }
    var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// «12:34 · 1080p · 483 МБ»
    var summary: String {
        var parts: [String] = []
        if let duration, duration > 0 { parts.append(Fmt.duration(duration)) }
        parts.append(isAudioOnly ? "Звук" : formatLabel)
        parts.append(Fmt.bytes(fileSize))
        return parts.joined(separator: " · ")
    }

    /// «1920 × 1080» — для экрана «Информация».
    var resolutionText: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width) × \(height)"
    }

    /// Имя, под которым файл уходит в «Поделиться»: название ролика, а не UUID.
    var shareFileName: String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t"))
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let base = String((cleaned.isEmpty ? "Видео" : cleaned).prefix(120))
        return "\(base) [\(isAudioOnly ? "звук" : formatLabel)].\(fileURL.pathExtension)"
    }
}
