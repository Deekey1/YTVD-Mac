import Foundation

/// Vimeo отдаёт свою главную страницу только браузеру: обычный запрос получает 403
/// ещё до всякой авторизации. Зато страница встраиваемого плеера открыта — через неё
/// ролик и достаётся.
public enum VimeoLinks {

    /// `vimeo.com/123456` → `player.vimeo.com/video/123456`
    /// `vimeo.com/123456/abc123` → `player.vimeo.com/video/123456?h=abc123` (скрытая ссылка)
    public static func playerURL(for url: URL) -> URL? {
        guard MediaSource.detect(url) == .vimeo else { return nil }
        guard let host = url.host?.lowercased(), !host.hasPrefix("player.") else { return nil }

        let parts = url.path.split(separator: "/").map(String.init)
        guard let id = parts.first, id.allSatisfy(\.isNumber), !id.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "player.vimeo.com"
        components.path = "/video/\(id)"

        // Второй кусок пути у скрытых роликов — ключ доступа.
        if parts.count > 1, let hash = parts.dropFirst().first,
           !hash.isEmpty, hash.allSatisfy({ $0.isHexDigit }) {
            components.queryItems = [URLQueryItem(name: "h", value: hash)]
        } else if let existing = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "h" }) {
            components.queryItems = [existing]
        }

        return components.url
    }

    /// Ссылки, которые стоит перебрать: сначала исходную, потом плеер.
    public static func candidates(for url: URL) -> [URL] {
        guard let player = playerURL(for: url) else { return [url] }
        return [url, player]
    }
}
