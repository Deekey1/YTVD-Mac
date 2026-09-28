import Foundation

/// Числа для интерфейса по-русски: «1,8 ГБ», «12:34», «12,4 МБ/с», «~11 с».
enum Fmt {

    /// Десятичные единицы — как в «Настройки → Основные → Хранилище».
    static func bytes(_ value: Int64) -> String {
        let units = ["Б", "КБ", "МБ", "ГБ", "ТБ"]
        var size = Double(max(0, value))
        var index = 0
        while size >= 1000, index < units.count - 1 {
            size /= 1000
            index += 1
        }
        // «483 МБ», но «1,8 ГБ» и «12,4 МБ»: дробь нужна, только пока число маленькое.
        let digits = index <= 1 || size >= 100 ? 0 : 1
        return number(size, digits: digits) + " " + units[index]
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        bytes(Int64(bytesPerSecond)) + "/с"
    }

    /// «0:42», «12:34», «1:02:03».
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Оставшееся время: «~11 с», «~4 мин», «~1 ч 5 мин».
    static func eta(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "~\(max(1, seconds)) с"
        case ..<3600: return "~\(Int((Double(seconds) / 60).rounded(.up))) мин"
        default:
            let minutes = seconds % 3600 / 60
            return "~\(seconds / 3600) ч" + (minutes > 0 ? " \(minutes) мин" : "")
        }
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction)) * 100).rounded(.down))) %"
    }

    static func number(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        return formatter.string(from: value as NSNumber) ?? String(value)
    }
}
