import SwiftData
import XCTest
@testable import VideoDownloader

/// Библиотека: сведения о файле, имена, место, дубликаты.
@MainActor
final class LibraryTests: XCTestCase {

    private func item(videoId: String = "aqz-KE-bpKQ", title: String = "Big Buck Bunny",
                      label: String = "1080p60", audio: Bool = false, date: Date = Date()) -> VideoItem {
        let id = UUID()
        return VideoItem(id: id, videoId: videoId, title: title, channel: "Blender", duration: 635,
                         width: 1920, height: 1080, fps: 60, formatLabel: label, codec: audio ? "aac" : "h264",
                         isAudioOnly: audio, fileName: "\(id.uuidString).\(audio ? "m4a" : "mp4")",
                         thumbnailName: nil, fileSize: 268_000_000,
                         sourceURL: "https://www.youtube.com/watch?v=\(videoId)", platform: "youtube",
                         downloadedAt: date)
    }

    func testMetadataForList() {
        XCTAssertEqual(item().summary, "10:35 · 1080p60 · 268 МБ")
        XCTAssertEqual(item(audio: true).summary, "10:35 · Звук · 268 МБ")
        XCTAssertEqual(item().resolutionText, "1920 × 1080")
        XCTAssertTrue(item().fileURL.path.contains("/VideoDownloader/Videos/"))
    }

    func testInternalFileNamesDoNotUseTitles() {
        let id = UUID()
        XCTAssertEqual(LibraryFiles.videoFileName(id: id, serverFileName: "Лекция: «Swift» [1080p].mp4", isAudioOnly: false),
                       "\(id.uuidString).mp4")
        XCTAssertEqual(LibraryFiles.videoFileName(id: id, serverFileName: nil, isAudioOnly: true), "\(id.uuidString).m4a")
        XCTAssertEqual(LibraryFiles.videoFileName(id: id, serverFileName: "strange.exe", isAudioOnly: false),
                       "\(id.uuidString).mp4", "чужое расширение не берём")
        XCTAssertEqual(LibraryFiles.thumbnailFileName(id: id), "\(id.uuidString).jpg")
    }

    func testShareNameIsHumanAndSafe() {
        let video = item(title: "Лекция 1/2: «Swift» — что нового?")
        XCTAssertEqual(video.shareFileName, "Лекция 1 2 «Swift» — что нового [1080p60].mp4")
        XCTAssertFalse(video.shareFileName.contains("/"))
        XCTAssertEqual(item(title: "   ").shareFileName, "Видео [1080p60].mp4")
    }

    func testStorageCheck() {
        XCTAssertThrowsError(try LibraryFiles.checkSpace(for: 3_000_000_000, free: 1_000_000_000)) { error in
            guard case AppError.notEnoughSpace = error else { return XCTFail("\(error)") }
            XCTAssertTrue(error.localizedDescription.hasPrefix("Недостаточно свободного места"))
        }
        XCTAssertNoThrow(try LibraryFiles.checkSpace(for: 500_000_000, free: 10_000_000_000))
        XCTAssertNoThrow(try LibraryFiles.checkSpace(for: nil, free: 1), "размер неизвестен — не мешаем")
    }

    func testDuplicatesByVideoId() throws {
        let container = try ModelContainer(for: VideoItem.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let older = item(label: "720p", date: Date(timeIntervalSinceNow: -3600))
        let newer = item(label: "1080p60")
        context.insert(older)
        context.insert(newer)
        context.insert(item(videoId: "other", title: "Другое видео"))
        try context.save()

        let found = Library.duplicates(of: "aqz-KE-bpKQ", in: context)
        XCTAssertEqual(found.map(\.formatLabel), ["1080p60", "720p"], "свежие копии первыми")
        XCTAssertTrue(Library.duplicates(of: "missing", in: context).isEmpty)
        XCTAssertEqual(Library.item(newer.id, in: context)?.formatLabel, "1080p60")
    }

    func testDeleteRemovesFileAndRecord() throws {
        let container = try ModelContainer(for: VideoItem.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        LibraryFiles.prepare()
        let video = item()
        try Data("x".utf8).write(to: video.fileURL)
        context.insert(video)
        try context.save()

        Library.delete(video, in: context)
        XCTAssertFalse(FileManager.default.fileExists(atPath: video.fileURL.path))
        XCTAssertTrue(Library.duplicates(of: "aqz-KE-bpKQ", in: context).isEmpty)
    }
}
