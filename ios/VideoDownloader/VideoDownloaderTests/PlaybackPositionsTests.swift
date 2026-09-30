import XCTest
@testable import VideoDownloader

/// Где остановился просмотр: правила «помнить или начать сначала» и надёжность файла.
@MainActor
final class PlaybackPositionsTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("positions-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var url: URL { directory.appendingPathComponent("Positions.json") }

    func testRemembersPlaceInTheMiddle() {
        let positions = PlaybackPositions(url: url)
        let id = UUID()
        positions.record(125, duration: 600, for: id)
        XCTAssertEqual(positions.resumeTime(for: id), 125)
        XCTAssertEqual(positions.progress(for: id) ?? 0, 125.0 / 600, accuracy: 0.0001)
    }

    func testBeginningAndEndAreNotRemembered() {
        let positions = PlaybackPositions(url: url)
        let id = UUID()
        positions.record(3, duration: 600, for: id)
        XCTAssertNil(positions.resumeTime(for: id), "первые секунды — смотреть сначала")

        positions.record(300, duration: 600, for: id)
        XCTAssertEqual(positions.resumeTime(for: id), 300)
        positions.record(595, duration: 600, for: id)
        XCTAssertNil(positions.resumeTime(for: id), "досмотрено — в следующий раз сначала")
        XCTAssertNil(positions.entries[id], "досмотренное забывается, а не хранится")
    }

    /// Плейлист продолжается с того видео, которое смотрели последним.
    func testLastStartedAmongPlaylist() {
        let positions = PlaybackPositions(url: url)
        let a = UUID(), b = UUID(), c = UUID(), outside = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        positions.record(100, duration: 600, for: a, now: start)
        positions.record(200, duration: 600, for: b, now: start.addingTimeInterval(60))
        positions.record(300, duration: 600, for: outside, now: start.addingTimeInterval(120))
        XCTAssertEqual(positions.lastStarted(among: [a, b, c]), b, "чужое видео не считается")

        positions.record(595, duration: 600, for: b, now: start.addingTimeInterval(180))
        XCTAssertEqual(positions.lastStarted(among: [a, b, c]), a, "досмотренное — уже не «продолжить»")
        XCTAssertNil(positions.lastStarted(among: [c]))
    }

    func testUnknownDurationStillResumes() {
        let positions = PlaybackPositions(url: url)
        let id = UUID()
        positions.record(42, duration: nil, for: id)
        XCTAssertEqual(positions.resumeTime(for: id), 42)
        XCTAssertNil(positions.progress(for: id), "без длительности полосу не рисуем")
        positions.record(50, duration: .nan, for: id)
        XCTAssertEqual(positions.resumeTime(for: id), 50, "NaN от плеера не ломает запись")
    }

    /// Главное: место читается заново из файла — как после перезагрузки телефона.
    func testSurvivesRestart() throws {
        let positions = PlaybackPositions(url: url)
        let first = UUID(), second = UUID()
        positions.record(61.5, duration: 1200, for: first)
        positions.record(10, duration: nil, for: second)
        positions.flush()

        let reopened = PlaybackPositions(url: url)
        XCTAssertEqual(reopened.resumeTime(for: first), 61.5)
        XCTAssertEqual(reopened.entries[first]?.duration, 1200)
        XCTAssertEqual(reopened.resumeTime(for: second), 10)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "временный файл заменяет основной, а не остаётся рядом")
    }

    func testMoveAndClearArePersisted() {
        let positions = PlaybackPositions(url: url)
        let old = UUID(), new = UUID()
        positions.record(200, duration: 900, for: old)
        positions.move(from: old, to: new)
        XCTAssertNil(positions.resumeTime(for: old))
        XCTAssertEqual(positions.resumeTime(for: new), 200)
        positions.flush()
        XCTAssertEqual(PlaybackPositions(url: url).resumeTime(for: new), 200)

        positions.clear(new)
        positions.flush()
        XCTAssertNil(PlaybackPositions(url: url).resumeTime(for: new))
    }

    func testDurableWriteReplacesWholeFile() throws {
        let file = directory.appendingPathComponent("file.json")
        XCTAssertTrue(DurableWriter.writeDurably(Data("первая, длинная версия".utf8), to: file))
        XCTAssertTrue(DurableWriter.writeDurably(Data("вторая".utf8), to: file))
        XCTAssertEqual(String(decoding: try Data(contentsOf: file), as: UTF8.self), "вторая",
                       "старое содержимое не проглядывает из-под нового")
    }

    func testCorruptFileStartsEmpty() throws {
        try Data("{ не json".utf8).write(to: url)
        let positions = PlaybackPositions(url: url)
        XCTAssertTrue(positions.entries.isEmpty)
        let id = UUID()
        positions.record(30, duration: 100, for: id)
        positions.flush()
        XCTAssertEqual(PlaybackPositions(url: url).resumeTime(for: id), 30)
    }
}
