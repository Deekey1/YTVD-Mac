import Foundation
import UIKit

/// Файлы библиотеки: Application Support/VideoDownloader/{Videos, Thumbnails}.
/// Имена внутренние — по UUID: названия роликов повторяются и содержат что угодно.
enum LibraryFiles {

    static let root: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VideoDownloader", isDirectory: true)

    static var videos: URL { root.appendingPathComponent("Videos", isDirectory: true) }
    static var thumbnails: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }
    /// Сюда фоновая загрузка кладёт готовый файл, пока его не внесли в библиотеку.
    static var incoming: URL { root.appendingPathComponent("Incoming", isDirectory: true) }

    static func prepare() {
        let fm = FileManager.default
        for directory in [videos, thumbnails, incoming] {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // Видео можно скачать заново — не раздуваем ими резервную копию в iCloud.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var videosURL = videos
        try? videosURL.setResourceValues(values)
    }

    /// Внутреннее имя видео: UUID и расширение от сервера (mp4 или m4a).
    static func videoFileName(id: UUID, serverFileName: String?, isAudioOnly: Bool) -> String {
        let known = ["mp4", "m4a", "mov", "mp3"]
        let serverExtension = serverFileName.map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
        let ext = serverExtension.flatMap { known.contains($0) ? $0 : nil } ?? (isAudioOnly ? "m4a" : "mp4")
        return "\(id.uuidString).\(ext)"
    }

    static func thumbnailFileName(id: UUID) -> String { "\(id.uuidString).jpg" }

    // MARK: - место

    static var freeSpace: Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Хватит ли места под файл — с запасом, чтобы не забить телефон под завязку.
    static func checkSpace(for size: Int64?, free: Int64? = LibraryFiles.freeSpace) throws {
        guard let size, size > 0, let free else { return }
        let needed = size + size / 10 + 200_000_000
        if free < needed { throw AppError.notEnoughSpace(needed: needed, free: free) }
    }

    // MARK: - обложки

    /// Уменьшенная копия обложки в JPEG: для списка хватает 640 точек по ширине.
    static func storeThumbnail(_ data: Data, name: String) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        let width: CGFloat = 640
        let scale = min(1, width / max(image.size.width, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else { return false }
        return (try? jpeg.write(to: thumbnails.appendingPathComponent(name), options: .atomic)) != nil
    }
}
