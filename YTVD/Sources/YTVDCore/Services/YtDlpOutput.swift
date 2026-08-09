import Foundation

/// Состояние скачивания одного потока.
public struct DownloadProgress: Equatable, Sendable {
    public var downloaded: Int64
    public var total: Int64?
    public var speed: Double?          // байт/с
    public var eta: Int?               // секунд

    public init(downloaded: Int64, total: Int64? = nil, speed: Double? = nil, eta: Int? = nil) {
        self.downloaded = downloaded; self.total = total; self.speed = speed; self.eta = eta
    }

    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, max(0, Double(downloaded) / Double(total)))
    }
}

/// Разобранная строка вывода yt-dlp.
public enum YtDlpLine: Equatable, Sendable {
    case progress(DownloadProgress)
    case destination(String)
    case merging(String)
    case extractingAudio
    case embeddingThumbnail
    case alreadyDownloaded(String)
    case failure(String)
    case other(String)
}

public enum YtDlpOutput {

    /// Шаблон прогресса: заставляем yt-dlp печатать сырые числа одной строкой.
    public static let progressTemplate =
        "YTVD|%(progress.downloaded_bytes)s|%(progress.total_bytes,progress.total_bytes_estimate)s"
        + "|%(progress.speed)s|%(progress.eta)s"

    public static func classify(_ rawLine: String) -> YtDlpLine {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return .other("") }

        if line.hasPrefix("YTVD|") {
            if let progress = parseProgress(line) { return .progress(progress) }
            return .other(line)
        }
        if let range = line.range(of: "[download] Destination: ") {
            return .destination(String(line[range.upperBound...]))
        }
        if let range = line.range(of: "[ExtractAudio] Destination: ") {
            _ = range
            return .extractingAudio
        }
        if line.contains("[Merger] Merging formats into") {
            let name = line.components(separatedBy: "\"").dropFirst().first ?? ""
            return .merging(name)
        }
        if line.hasPrefix("[EmbedThumbnail]") { return .embeddingThumbnail }
        if line.contains("has already been downloaded") {
            let name = line.replacingOccurrences(of: "[download] ", with: "")
                .replacingOccurrences(of: " has already been downloaded", with: "")
            return .alreadyDownloaded(name)
        }
        if line.hasPrefix("ERROR:") || line.hasPrefix("yt-dlp: error:") {
            return .failure(cleanError(line))
        }
        return .other(line)
    }

    /// «YTVD|1234|5678|1048576.0|42» → прогресс. Отсутствующие поля yt-dlp печатает как NA/None.
    public static func parseProgress(_ line: String) -> DownloadProgress? {
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 5, parts[0] == "YTVD" else { return nil }

        func number(_ text: String) -> Double? {
            let t = text.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t != "NA", t != "None", t != "-" else { return nil }
            return Double(t)
        }

        guard let downloaded = number(parts[1]) else { return nil }
        return DownloadProgress(
            downloaded: Int64(downloaded),
            total: number(parts[2]).map { Int64($0) },
            speed: number(parts[3]),
            eta: number(parts[4]).map { Int($0) })
    }

    /// Превращает техническое сообщение yt-dlp в человеческое.
    /// Площадку передаём, чтобы подсказка была по делу: Rutube и VK ждут российский IP,
    /// а Vimeo и YouTube наоборот блокируют адреса дата-центров, которыми пользуется VPN.
    public static func humanError(_ raw: String, source: MediaSource = .other,
                                  viaVPN: Bool = false, hasCookies: Bool = false,
                                  canMerge: Bool = true, hasJSRuntime: Bool = true) -> String {
        let text = cleanError(raw)
        let lowered = text.lowercased()
        let vpnNote = viaVPN ? " Сейчас трафик идёт через VPN." : ""

        /// Что советовать про вход: включить cookies или проверить, что вход в браузере есть.
        let loginAdvice = hasCookies
            ? "Проверьте, что в выбранном браузере вы действительно вошли в Vimeo."
            : "Войдите в Vimeo в браузере и включите в настройках «Брать cookies из браузера»."

        // Vimeo просит вход — тут поможет только вход, адрес ни при чём.
        if lowered.contains("only works when logged-in") || lowered.contains("only works when logged in") {
            return "Vimeo отдаёт это видео только тем, кто вошёл. " + loginAdvice
        }

        // Отказ по IP — самая частая беда при включённом VPN.
        if isAddressRelated(text) {
            switch source {
            case .rutube, .vk:
                // Описание ролика часто приходит нормально, а видео раздаёт другой сервер —
                // и вот он уже смотрит на страну адреса.
                let refused = lowered.contains("connection refused")
                    || lowered.contains("failed to establish a new connection")
                return (refused
                        ? "Сервер раздачи видео отклонил соединение. "
                        : "Площадка не пускает с этого адреса. ")
                     + "Rutube и VK Видео работают в основном с российских IP — выключите VPN "
                     + "или выберите Россию." + vpnNote
            case .vimeo:
                // Vimeo отклоняет анонимные запросы и без всякого VPN: у него свой
                // ключ доступа, который выдаётся не всем. Вход снимает вопрос целиком.
                return "Vimeo отклонил запрос без входа — он часто так делает. " + loginAdvice
                     + vpnNote
            default:
                return "Площадка заблокировала адрес, с которого пришёл запрос — обычно так "
                     + "отсекают VPN. Выключите VPN для этого сайта или добавьте его в "
                     + "исключения." + vpnNote
            }
        }

        if lowered.contains("video unavailable") { return "Видео недоступно" }
        if lowered.contains("privacyerror") || lowered.contains("privacy error") {
            return "Владелец ограничил доступ к ролику — Vimeo отдаёт его только на "
                 + "разрешённых сайтах. Скачать его нельзя."
        }
        if source == .vimeo, lowered.contains("401"), lowered.contains("unauthorized") {
            return "Владелец ограничил доступ к ролику — Vimeo не отдаёт его сторонним "
                 + "программам. Скачать его нельзя."
        }
        if lowered.contains("private video") { return "Это приватное видео" }
        if lowered.contains("members-only") || lowered.contains("join this channel") {
            return "Видео только для подписчиков канала"
        }
        if lowered.contains("sign in to confirm your age") || lowered.contains("age") && lowered.contains("confirm") {
            return "Возрастное ограничение — нужен вход в аккаунт"
        }
        if lowered.contains("sign in to confirm") || lowered.contains("not a bot") {
            return "YouTube требует подтвердить, что вы не робот. Включите в настройках "
                 + "«Брать cookies из браузера» — обычно этого хватает."
        }
        if lowered.contains("available in your country") || lowered.contains("in your location")
            || (lowered.contains("geo") && lowered.contains("block")) {
            return "Ролик заблокирован в вашем регионе"
        }
        if lowered.contains("unable to download webpage") || lowered.contains("failed to resolve")
            || lowered.contains("network is unreachable") || lowered.contains("timed out") {
            return "Нет связи с площадкой — проверьте интернет"
        }
        if lowered.contains("unsupported url") { return "Эта ссылка не поддерживается" }
        if lowered.contains("is not a valid url") { return "Ссылка выглядит неправильно" }
        // YouTube требует решить задачу на JavaScript. Без исполнителя JS список форматов
        // приходит пустым — остаются одни раскадровки, и yt-dlp говорит «формат недоступен».
        if lowered.contains("n challenge solving failed")
            || lowered.contains("only images are available")
            || (lowered.contains("requested format is not available") && !hasJSRuntime) {
            return "YouTube не отдал ни одного формата: не найден исполнитель JavaScript, "
                 + "без него площадку не открыть. Установите его командой: brew install deno"
        }
        if lowered.contains("requested format is not available") {
            return "Такого формата у ролика нет — попробуйте другое качество"
        }
        if lowered.contains("live event will begin") || lowered.contains("premieres in") {
            return "Трансляция ещё не началась"
        }
        if lowered.contains("no space left") { return "На диске нет места" }

        return text.isEmpty ? "Не удалось получить данные" : text
    }

    /// Похоже ли, что площадка отказала именно из-за адреса, с которого пришёл запрос.
    /// Сюда же неудачная выдача OAuth-токена Vimeo и обрыв по таймауту: у них общий корень.
    public static func isAddressRelated(_ raw: String) -> Bool {
        let lowered = raw.lowercased()
        if lowered.contains("data center ip") || lowered.contains("vpn/proxy") { return true }
        if lowered.contains("403") && (lowered.contains("impersonate") || lowered.contains("forbidden")) {
            return true
        }
        if lowered.contains("oauth token") && (lowered.contains("401") || lowered.contains("failed to fetch")) {
            return true
        }
        if lowered.contains("unable to fetch new oauth tokens") { return true }
        if lowered.contains("curl: (28)") || lowered.contains("operation too slow") { return true }
        // Сервер раздачи видео (CDN) может просто отбить соединение — так делают,
        // когда адрес не из нужной страны.
        if lowered.contains("connection refused") || lowered.contains("errno 61") { return true }
        if lowered.contains("failed to establish a new connection") { return true }
        return false
    }

    private static func cleanError(_ raw: String) -> String {
        var text = raw
        for prefix in ["ERROR: ", "yt-dlp: error: ", "ERROR:"] {
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        }
        // Убираем технический хвост вида «; please report this issue on ...»
        if let cut = text.range(of: "; please report") { text = String(text[..<cut.lowerBound]) }
        if let cut = text.range(of: ". Use --") { text = String(text[..<cut.lowerBound]) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
