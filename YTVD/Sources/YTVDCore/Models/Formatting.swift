import Foundation

/// Форматирование чисел и времени по-русски: запятая как разделитель дробной части,
/// двоичные килобайты, правильные окончания у счётных слов.
public enum Fmt {

    private static let kb: Double = 1024
    private static let mb: Double = 1024 * 1024
    private static let gb: Double = 1024 * 1024 * 1024

    private static func decimal(_ value: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// «96 КБ» · «9,8 МБ» · «318 МБ» · «1,40 ГБ»
    public static func bytes(_ count: Int64) -> String {
        let v = Double(max(0, count))
        if v < mb { return "\(Int((v / kb).rounded())) КБ" }
        let inMB = v / mb
        if inMB < 10 { return "\(decimal(inMB, 1)) МБ" }
        if inMB < 1024 { return "\(Int(inMB.rounded())) МБ" }
        return "\(decimal(v / gb, 2)) ГБ"
    }

    /// Короткая запись для строки прогресса: «79 / 318 МБ»
    public static func progressBytes(done: Int64, total: Int64) -> String {
        let unitIsGB = Double(total) >= gb
        let scale = unitIsGB ? gb : mb
        let suffix = unitIsGB ? "ГБ" : "МБ"
        let places = unitIsGB ? 2 : 0
        return "\(decimal(Double(done) / scale, places)) / \(decimal(Double(total) / scale, places)) \(suffix)"
    }

    /// «12,4 МБ/с» · «860 КБ/с»
    public static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "—" }
        if bytesPerSecond < mb { return "\(Int((bytesPerSecond / kb).rounded())) КБ/с" }
        return "\(decimal(bytesPerSecond / mb, 1)) МБ/с"
    }

    /// «10:32» · «1:02:03»
    public static func duration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    /// Оставшееся время в компактном виде: «0:25»
    public static func eta(_ seconds: Int) -> String { duration(seconds) }

    /// Затраченное время словами: «26 с» · «2:06»
    public static func elapsed(_ seconds: Int) -> String {
        seconds < 60 ? "\(max(0, seconds)) с" : duration(seconds)
    }

    /// «1 вариант» · «2 варианта» · «5 вариантов»
    public static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        "\(n) \(pluralWord(n, one, few, many))"
    }

    public static func pluralWord(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = abs(n) % 100, b = a % 10
        if a > 10 && a < 20 { return many }
        if b == 1 { return one }
        if b >= 2 && b <= 4 { return few }
        return many
    }

    /// «4,2 млн просмотров»
    public static func views(_ count: Int) -> String {
        switch count {
        case ..<1_000:
            return plural(count, "просмотр", "просмотра", "просмотров")
        case ..<1_000_000:
            return "\(decimal(Double(count) / 1_000, 1)) тыс. просмотров"
        case ..<1_000_000_000:
            return "\(decimal(Double(count) / 1_000_000, 1)) млн просмотров"
        default:
            return "\(decimal(Double(count) / 1_000_000_000, 1)) млрд просмотров"
        }
    }

    /// Дата выкладки yt-dlp приходит строкой «20230114».
    public static func uploadDate(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard raw.count == 8,
              let year = Int(raw.prefix(4)),
              let month = Int(raw.dropFirst(4).prefix(2)),
              let day = Int(raw.suffix(2)),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        return ago(date, now: now, calendar: calendar)
    }

    /// «10 мин назад» · «вчера» · «2 года назад»
    public static func ago(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "только что" }
        if seconds < 3600 { return plural(seconds / 60, "минуту", "минуты", "минут") + " назад" }
        if seconds < 86_400 { return plural(seconds / 3600, "час", "часа", "часов") + " назад" }

        let days = seconds / 86_400
        if days == 1 { return "вчера" }
        if days < 7 { return plural(days, "день", "дня", "дней") + " назад" }
        if days < 31 { return plural(days / 7, "неделю", "недели", "недель") + " назад" }
        if days < 365 { return plural(days / 30, "месяц", "месяца", "месяцев") + " назад" }
        return plural(days / 365, "год", "года", "лет") + " назад"
    }

    /// Убирает из названия символы, недопустимые в имени файла.
    public static func safeFileName(_ title: String, maxLength: Int = 120) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var cleaned = title.components(separatedBy: forbidden).joined(separator: " ")
        while cleaned.contains("  ") { cleaned = cleaned.replacingOccurrences(of: "  ", with: " ") }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count > maxLength { cleaned = String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespaces) }
        return cleaned.isEmpty ? "video" : cleaned
    }
}
