import XCTest
@testable import YTVDCore

final class FormattingTests: XCTestCase {

    func testBytesUsesRussianDecimalCommaAndBinaryUnits() {
        XCTAssertEqual(Fmt.bytes(96_000), "94 КБ")
        XCTAssertEqual(Fmt.bytes(10_276_045), "9,8 МБ")
        XCTAssertEqual(Fmt.bytes(333_447_168), "318 МБ")
        XCTAssertEqual(Fmt.bytes(1_503_238_553), "1,40 ГБ")
    }

    func testBytesHandlesZeroAndNegative() {
        XCTAssertEqual(Fmt.bytes(0), "0 КБ")
        XCTAssertEqual(Fmt.bytes(-5), "0 КБ")
    }

    func testProgressBytesKeepsBothNumbersInOneUnit() {
        let mb: Int64 = 1024 * 1024
        XCTAssertEqual(Fmt.progressBytes(done: 79 * mb, total: 318 * mb), "79 / 318 МБ")
        XCTAssertEqual(Fmt.progressBytes(done: 512 * mb, total: 2048 * mb), "0,50 / 2,00 ГБ")
    }

    func testSpeed() {
        XCTAssertEqual(Fmt.speed(13_002_342), "12,4 МБ/с")
        XCTAssertEqual(Fmt.speed(880_640), "860 КБ/с")
        XCTAssertEqual(Fmt.speed(0), "—")
        XCTAssertEqual(Fmt.speed(.nan), "—")
    }

    func testDuration() {
        XCTAssertEqual(Fmt.duration(632), "10:32")
        XCTAssertEqual(Fmt.duration(3723), "1:02:03")
        XCTAssertEqual(Fmt.duration(0), "0:00")
        XCTAssertEqual(Fmt.duration(-10), "0:00")
    }

    func testPluralFollowsRussianRules() {
        XCTAssertEqual(Fmt.plural(1, "вариант", "варианта", "вариантов"), "1 вариант")
        XCTAssertEqual(Fmt.plural(2, "вариант", "варианта", "вариантов"), "2 варианта")
        XCTAssertEqual(Fmt.plural(5, "вариант", "варианта", "вариантов"), "5 вариантов")
        XCTAssertEqual(Fmt.plural(11, "вариант", "варианта", "вариантов"), "11 вариантов")
        XCTAssertEqual(Fmt.plural(21, "вариант", "варианта", "вариантов"), "21 вариант")
        XCTAssertEqual(Fmt.plural(114, "файл", "файла", "файлов"), "114 файлов")
        XCTAssertEqual(Fmt.plural(0, "файл", "файла", "файлов"), "0 файлов")
    }

    func testViews() {
        XCTAssertEqual(Fmt.views(842), "842 просмотра")
        XCTAssertEqual(Fmt.views(12_400), "12,4 тыс. просмотров")
        XCTAssertEqual(Fmt.views(4_200_000), "4,2 млн просмотров")
    }

    func testAgo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(Fmt.ago(now.addingTimeInterval(-30), now: now), "только что")
        XCTAssertEqual(Fmt.ago(now.addingTimeInterval(-600), now: now), "10 минут назад")
        XCTAssertEqual(Fmt.ago(now.addingTimeInterval(-7200), now: now), "2 часа назад")
        XCTAssertEqual(Fmt.ago(now.addingTimeInterval(-86_400), now: now), "вчера")
        XCTAssertEqual(Fmt.ago(now.addingTimeInterval(-86_400 * 3), now: now), "3 дня назад")
        XCTAssertEqual(Fmt.ago(now.addingTimeInterval(-86_400 * 400), now: now), "1 год назад")
    }

    func testUploadDateParsesYtDlpFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2024, month: 1, day: 20))!
        XCTAssertEqual(Fmt.uploadDate("20240114", now: now, calendar: calendar), "6 дней назад")
        XCTAssertNil(Fmt.uploadDate("2024", now: now, calendar: calendar))
        XCTAssertNil(Fmt.uploadDate("notadate", now: now, calendar: calendar))
    }

    func testSafeFileNameStripsPathSeparators() {
        XCTAssertEqual(Fmt.safeFileName("A/B: C?"), "A B C")
        XCTAssertEqual(Fmt.safeFileName("Ролик | часть 2"), "Ролик часть 2")
        XCTAssertEqual(Fmt.safeFileName("   "), "video")
        XCTAssertEqual(Fmt.safeFileName(String(repeating: "я", count: 200)).count, 120)
    }
}
