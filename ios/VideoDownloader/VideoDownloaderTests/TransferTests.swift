import XCTest
import YTVDAPI
@testable import VideoDownloader

/// Карточка загрузки: какой этап показать и что писать про прогресс.
final class TransferTests: XCTestCase {

    /// Даты в JSON — с точностью до секунды, поэтому в тестах берём ровную.
    private static let moment = Date(timeIntervalSince1970: 1_790_552_191)

    private func transfer(_ status: JobStatus? = nil, progress: Double? = nil) throws -> Transfer {
        let video = try API.decoder.decode(VideoInfo.self, from: Data(APIDecodingTests.resolveJSON.utf8))
        var transfer = Transfer(id: UUID(), jobId: "job", server: URL(string: "http://192.168.1.10:8765")!,
                                video: video, format: video.formats[1], createdAt: Self.moment)
        if let status {
            transfer.job = JobInfo(jobId: "job", status: status, progress: progress,
                                   downloadedBytes: 356_000_000, totalBytes: 483_000_000, speed: 12_400_000,
                                   eta: 11, videoId: video.id, title: video.title, sourceUrl: video.sourceUrl,
                                   formatId: "h1080-60", formatLabel: "1080p60",
                                   createdAt: Self.moment, updatedAt: Self.moment)
        }
        return transfer
    }

    /// Неразрывные пробелы и склейки — на экране, в проверках сравниваем обычный текст.
    private func plain(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{2060}", with: "")
    }

    func testDetailPartsDoNotBreakInside() {
        XCTAssertEqual(Transfer.unbreakable("589 КБ/с"), "589\u{00A0}КБ/\u{2060}с")
    }

    func testMacStages() throws {
        XCTAssertEqual(try transfer().stageTitle, "Отправка на Mac…")
        XCTAssertEqual(try transfer(.queued).stageTitle, "В очереди на Mac")
        XCTAssertEqual(try transfer(.downloadingVideo, progress: 0.74).stageTitle, "Mac скачивает видео")
        XCTAssertEqual(plain(try transfer(.downloadingVideo, progress: 0.74).detailLine),
                       "74 % · 356 МБ из 483 МБ · 12,4 МБ/с · ~11 с")
    }

    func testMergingHasNoFakeHundredPercent() throws {
        let merging = try transfer(.merging, progress: 1)
        XCTAssertEqual(merging.stageTitle, "Объединение видео и аудио…")
        XCTAssertNil(merging.fraction, "пока ffmpeg работает, показываем крутилку, а не 100 %")
        let resolving = try transfer(.resolving, progress: 0)
        XCTAssertNil(resolving.fraction)
    }

    func testTransferToPhone() throws {
        var item = try transfer(.ready)
        item.phase = .transfer
        item.received = 134_000_000
        item.expected = 268_000_000
        item.speed = 25_000_000
        XCTAssertEqual(item.stageTitle, "Передача на iPhone")
        XCTAssertEqual(item.fraction, 0.5)
        XCTAssertEqual(plain(item.detailLine), "50 % · 134 МБ из 268 МБ · 25 МБ/с · ~6 с")
    }

    func testFailedTransferShowsNoProgress() throws {
        var item = try transfer(.downloadingVideo, progress: 0.63)
        item.phase = .failed
        item.error = "Задание на Mac не найдено — скачайте заново"
        XCTAssertFalse(item.isActive)
        XCTAssertNil(item.fraction, "никаких «вечных 63 %»")
        XCTAssertNil(item.detailLine)
    }

    func testTransferSurvivesRestart() throws {
        var item = try transfer(.transcoding, progress: 0.4)
        item.replaces = UUID()
        item.attempts = 2
        let data = try API.encoder.encode([item])
        let restored = try API.decoder.decode([Transfer].self, from: data)
        XCTAssertEqual(restored.first, item)
    }
}
