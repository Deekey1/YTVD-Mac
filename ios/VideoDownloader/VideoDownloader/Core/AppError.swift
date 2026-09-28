import Foundation
import YTVDAPI

/// Ошибки в том виде, в каком их видит пользователь. Технические подробности — в журнал.
enum AppError: LocalizedError, Equatable {
    case noServer
    case serverUnavailable
    case unauthorized
    case invalidURL
    case notEnoughSpace(needed: Int64, free: Int64)
    case server(code: String, message: String)
    case network(String)
    case photosDenied

    var errorDescription: String? {
        switch self {
        case .noServer:
            "Mac не выбран — укажите его в настройках"
        case .serverUnavailable:
            "Mac недоступен. Проверьте, что YTVD запущен, сервер для iPhone включён, а iPhone в той же сети"
        case .unauthorized:
            "Mac не узнаёт этот iPhone — сопрягите их заново в настройках"
        case .invalidURL:
            "Нужна ссылка на YouTube, Vimeo, Rutube или VK Видео"
        case .notEnoughSpace(let needed, let free):
            "Недостаточно свободного места на iPhone: нужно около \(Fmt.bytes(needed)), свободно \(Fmt.bytes(free))"
        case .server(_, let message):
            message
        case .network(let message):
            message
        case .photosDenied:
            "Нет доступа к «Фото» — разрешите его в Настройках iPhone"
        }
    }

    /// Машиночитаемый код ошибки сервера, если это она.
    var serverCode: String? {
        if case .server(let code, _) = self { return code }
        return nil
    }

    static func from(_ error: Error) -> AppError {
        if let app = error as? AppError { return app }
        if let body = error as? APIErrorBody {
            return body.code == APIErrorCode.unauthorized.rawValue
                ? .unauthorized : .server(code: body.code, message: body.message)
        }
        if let url = error as? URLError {
            switch url.code {
            case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost,
                 .notConnectedToInternet, .dnsLookupFailed, .cannotLoadFromNetwork,
                 .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
                return .serverUnavailable
            case .appTransportSecurityRequiresSecureConnection:
                if let host = url.failingURL?.host(), Connection.isTailnet(host) {
                    return .network("По адресу 100.x iOS не пускает — введите имя Mac в Tailscale "
                                    + "вида macbook-pro.tail1234.ts.net: оно показано на Mac в настройках сервера")
                }
                return .network("iOS не пустил соединение с Mac: адрес не похож на домашнюю сеть")
            default:
                return .network("Ошибка сети: \(url.localizedDescription)")
            }
        }
        return .network(error.localizedDescription)
    }
}
