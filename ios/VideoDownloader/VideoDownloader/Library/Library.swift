import AVFoundation
import Foundation
import os
import SwiftData

/// Хранилище сведений о видео. Один контейнер на всё приложение — им пользуется
/// и интерфейс, и фоновая загрузка, когда система будит приложение без окна.
enum Persistence {
    @MainActor static let container: ModelContainer = {
        // Место указываем явно: иначе SwiftData уносит базу в общий контейнер App Group,
        // а расширению «Поделиться» она не нужна.
        LibraryFiles.prepare()
        // Плейлисты и поле «Избранное» появились позже: SwiftData дописывает их в прежнюю
        // базу сама — новая сущность и поле со значением по умолчанию.
        let configuration = ModelConfiguration(
            schema: Schema([VideoItem.self, Playlist.self]),
            url: LibraryFiles.root.appendingPathComponent("Library.store"),
            cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: VideoItem.self, Playlist.self, configurations: configuration)
        } catch {
            fatalError("Не открылась библиотека: \(error)")
        }
    }()
}

/// Операции с библиотекой.
@MainActor
enum Library {

    private static let log = Logger(subsystem: "studio.dk.videodownloader", category: "library")

    /// Уже скачанные копии этого ролика — самые свежие первыми.
    static func duplicates(of videoId: String, in context: ModelContext) -> [VideoItem] {
        let id = videoId
        let descriptor = FetchDescriptor<VideoItem>(
            predicate: #Predicate { $0.videoId == id },
            sortBy: [SortDescriptor(\.downloadedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func item(_ id: UUID, in context: ModelContext) -> VideoItem? {
        let target = id
        var descriptor = FetchDescriptor<VideoItem>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Удаляет запись вместе с файлом и обложкой, убирает видео из плейлистов
    /// и забывает место, где остановился просмотр.
    static func delete(_ item: VideoItem, in context: ModelContext,
                       positions: PlaybackPositions = .shared) {
        let fm = FileManager.default
        try? fm.removeItem(at: item.fileURL)
        if let thumbnail = item.thumbnailURL { try? fm.removeItem(at: thumbnail) }
        log.info("удалено видео \(item.id.uuidString, privacy: .public)")
        Playlists.forget(item.id, in: context)
        positions.clear(item.id)
        context.delete(item)
        try? context.save()
    }

    /// Тот же ролик скачан в другом качестве и заменяет прежний. Новая запись наследует
    /// «Избранное», место в плейлистах и позицию просмотра — время у ролика то же.
    static func replace(_ previous: VideoItem, with item: VideoItem, in context: ModelContext,
                        positions: PlaybackPositions = .shared) {
        if previous.isFavorite { item.isFavorite = true }
        Playlists.substitute(previous.id, with: item.id, in: context)
        positions.move(from: previous.id, to: item.id)
        delete(previous, in: context, positions: positions)
    }

    static func setFavorite(_ item: VideoItem, _ favorite: Bool, in context: ModelContext) {
        item.isFavorite = favorite
        try? context.save()
    }

    /// Настоящий размер кадра из файла — с учётом поворота у вертикальных роликов.
    nonisolated static func videoSize(of url: URL) async -> (width: Int, height: Int)? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return (Int(abs(rect.width).rounded()), Int(abs(rect.height).rounded()))
    }
}
