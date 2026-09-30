import SwiftData
import XCTest
@testable import VideoDownloader

/// Плейлисты и избранное: порядок, повторы, удаление и замена видео.
@MainActor
final class PlaylistTests: XCTestCase {

    private var positionsURL: URL!
    /// База живёт, пока идёт тест: контекст сам её не удерживает.
    private var container: ModelContainer?

    override func setUp() {
        super.setUp()
        positionsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("playlist-tests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: positionsURL)
        container = nil
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: VideoItem.self, Playlist.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        return container.mainContext
    }

    private func video(_ title: String, duration: Double? = 60, in context: ModelContext) -> VideoItem {
        let id = UUID()
        let item = VideoItem(id: id, videoId: title, title: title, channel: nil, duration: duration,
                             width: 1920, height: 1080, fps: 30, formatLabel: "1080p", codec: "h264",
                             isAudioOnly: false, fileName: "\(id.uuidString).mp4", thumbnailName: nil,
                             fileSize: 1_000_000, sourceURL: "https://example.com/\(title)", platform: "youtube")
        context.insert(item)
        return item
    }

    func testCreateKeepsChosenOrderWithoutDuplicates() throws {
        let context = try makeContext()
        let a = video("a", in: context), b = video("b", in: context), c = video("c", in: context)
        let playlist = Playlists.create(name: "  Вечер \n кино  ", items: [c, a, c, b], in: context)
        XCTAssertEqual(playlist.name, "Вечер кино")
        XCTAssertEqual(Playlists.items(of: playlist, in: context).map(\.title), ["c", "a", "b"])
    }

    func testAddAppendsOnlyNewVideos() throws {
        let context = try makeContext()
        let a = video("a", in: context), b = video("b", in: context), c = video("c", in: context)
        let playlist = Playlists.create(name: "Список", items: [a, b], in: context)
        Playlists.add([b, c, a], to: playlist, in: context)
        XCTAssertEqual(Playlists.items(of: playlist, in: context).map(\.title), ["a", "b", "c"])
    }

    /// Те же индексы, что присылает onMove в SwiftUI.
    func testMoveMatchesOnMoveSemantics() {
        let ids = (0..<4).map { _ in UUID() }
        func moved(_ source: IndexSet, _ destination: Int) -> [Int] {
            let playlist = Playlist(name: "p", itemIDs: ids)
            playlist.move(fromOffsets: source, toOffset: destination)
            return playlist.itemIDs.map { ids.firstIndex(of: $0)! }
        }
        XCTAssertEqual(moved([0], 3), [1, 2, 0, 3])
        XCTAssertEqual(moved([3], 0), [3, 0, 1, 2])
        XCTAssertEqual(moved([1, 2], 4), [0, 3, 1, 2])
        XCTAssertEqual(moved([2], 2), [0, 1, 2, 3], "на своё же место — без изменений")

        let playlist = Playlist(name: "p", itemIDs: ids)
        playlist.remove(atOffsets: [0, 2])
        XCTAssertEqual(playlist.itemIDs, [ids[1], ids[3]])
    }

    func testDeletedVideoLeavesPlaylistsAndPositions() throws {
        let context = try makeContext()
        let positions = PlaybackPositions(url: positionsURL)
        let a = video("a", in: context), b = video("b", in: context), c = video("c", in: context)
        let first = Playlists.create(name: "1", items: [a, b, c], in: context)
        let second = Playlists.create(name: "2", items: [b], in: context)
        positions.record(30, duration: 60, for: b.id)

        Library.delete(b, in: context, positions: positions)

        XCTAssertEqual(Playlists.items(of: first, in: context).map(\.title), ["a", "c"])
        XCTAssertTrue(second.itemIDs.isEmpty)
        XCTAssertNil(positions.resumeTime(for: b.id))
    }

    /// Тот же ролик в другом качестве: избранное, место в плейлисте и позиция — у новой записи.
    func testReplacementInheritsFavoritePlaylistAndPosition() throws {
        let context = try makeContext()
        let positions = PlaybackPositions(url: positionsURL)
        let a = video("a", in: context), old = video("old", duration: 600, in: context), c = video("c", in: context)
        old.isFavorite = true
        let playlist = Playlists.create(name: "Список", items: [a, old, c], in: context)
        positions.record(245, duration: 600, for: old.id)
        let new = video("new", duration: 600, in: context)

        Library.replace(old, with: new, in: context, positions: positions)

        XCTAssertTrue(new.isFavorite)
        XCTAssertEqual(Playlists.items(of: playlist, in: context).map(\.title), ["a", "new", "c"])
        XCTAssertEqual(positions.resumeTime(for: new.id), 245)
        XCTAssertNil(Library.item(old.id, in: context))
    }

    func testFavoriteIsSaved() throws {
        let context = try makeContext()
        let a = video("a", in: context)
        Library.setFavorite(a, true, in: context)
        let favorites = try context.fetch(FetchDescriptor<VideoItem>(predicate: #Predicate { $0.isFavorite }))
        XCTAssertEqual(favorites.map(\.title), ["a"])
    }

    func testSuggestedNameAndDuration() throws {
        XCTAssertEqual(Playlists.suggestedName(existing: []), "Плейлист 1")
        XCTAssertEqual(Playlists.suggestedName(existing: ["Плейлист 2"]), "Плейлист 3")
        XCTAssertEqual(Playlists.suggestedName(existing: ["Мой", "Плейлист 3"]), "Плейлист 4")
        XCTAssertEqual(Playlists.suggestedName(existing: ["Музыка", "Вечер кино"]), "Плейлист 1")

        let context = try makeContext()
        let items = [video("a", duration: 90, in: context), video("b", duration: nil, in: context),
                     video("c", duration: 30, in: context)]
        XCTAssertEqual(Playlists.totalDuration(of: items), 120)
    }
}
