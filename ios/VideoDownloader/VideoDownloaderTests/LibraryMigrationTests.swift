import SwiftData
import XCTest
@testable import VideoDownloader

/// База из версии 1.3: только видео — без плейлистов и без «Избранного».
/// Модель переписана один в один с той, что была в приложении.
enum LibrarySchema13: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 3, 0)
    static var models: [any PersistentModel.Type] { [VideoItem.self] }

    @Model
    final class VideoItem {
        @Attribute(.unique) var id: UUID
        var videoId: String
        var title: String
        var channel: String?
        var duration: Double?
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

        init(id: UUID, title: String, downloadedAt: Date) {
            self.id = id
            self.videoId = "old-\(title)"
            self.title = title
            self.channel = "Канал"
            self.duration = 600
            self.width = 1920
            self.height = 1080
            self.fps = 30
            self.formatLabel = "1080p"
            self.codec = "h264"
            self.isAudioOnly = false
            self.fileName = "\(id.uuidString).mp4"
            self.thumbnailName = nil
            self.fileSize = 123_456_789
            self.sourceURL = "https://example.com/\(title)"
            self.platform = "youtube"
            self.downloadedAt = downloadedAt
        }
    }
}

/// Обновление приложения не должно терять библиотеку: новая версия открывает прежнюю базу,
/// а не падает на старте.
@MainActor
final class LibraryMigrationTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testOpensLibraryFromVersion13() throws {
        let url = directory.appendingPathComponent("Library.store")
        let first = UUID(), second = UUID()
        let date = Date(timeIntervalSince1970: 1_790_000_000)

        // Так базу оставила версия 1.3.
        do {
            let old = try ModelContainer(for: Schema(versionedSchema: LibrarySchema13.self),
                                         configurations: ModelConfiguration(url: url))
            let context = ModelContext(old)
            context.insert(LibrarySchema13.VideoItem(id: first, title: "Первое", downloadedAt: date))
            context.insert(LibrarySchema13.VideoItem(id: second, title: "Второе",
                                                     downloadedAt: date.addingTimeInterval(60)))
            try context.save()
        }

        // Так её открывает новая версия — теми же параметрами, что и Persistence.
        let container = try ModelContainer(
            for: VideoItem.self, Playlist.self,
            configurations: ModelConfiguration(schema: Schema([VideoItem.self, Playlist.self]), url: url))
        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<VideoItem>(sortBy: [SortDescriptor(\.downloadedAt)]))
        XCTAssertEqual(items.map(\.id), [first, second])
        XCTAssertEqual(items.map(\.title), ["Первое", "Второе"])
        XCTAssertEqual(items.first?.fileSize, 123_456_789)
        XCTAssertEqual(items.first?.formatLabel, "1080p")
        XCTAssertFalse(items.contains(where: \.isFavorite), "старые видео — не в избранном")

        // И новое сразу работает с прежними записями.
        Library.setFavorite(items[1], true, in: context)
        let playlist = Playlists.create(name: "После обновления", items: [items[1], items[0]], in: context)
        XCTAssertEqual(Playlists.items(of: playlist, in: context).map(\.title), ["Второе", "Первое"])
        let favorites = try context.fetch(FetchDescriptor<VideoItem>(predicate: #Predicate { $0.isFavorite }))
        XCTAssertEqual(favorites.map(\.id), [second])
    }
}
