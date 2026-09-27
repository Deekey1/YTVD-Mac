import Foundation
import Security

/// Доступ к серверу: постоянный токен и одноразовый код сопряжения.
///
/// Вводить на телефоне 43 символа никто не будет, поэтому Mac показывает шестизначный
/// код на 5 минут, а iPhone меняет его на токен. Подобрать код нельзя: после пяти
/// неверных попыток он сгорает, а новый появляется только по кнопке на самом Mac.
public final class PairingManager: @unchecked Sendable {

    public enum PairResult: Equatable {
        case success(token: String)
        case invalid
        /// Код сгорел от неверных попыток или истёк — нужен новый.
        case expired
    }

    public static let maxAttempts = 5

    private let tokenURL: URL
    private let lock = NSLock()
    private var cachedToken: String?
    private var code: (value: String, expires: Date, attempts: Int)?
    private let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.tokenURL = directory.appendingPathComponent("token")
        self.now = now
    }

    // MARK: - токен

    /// Токен сервера. Создаётся при первом обращении и хранится с правами 0600.
    public var token: String {
        lock.lock(); defer { lock.unlock() }
        if let cachedToken { return cachedToken }
        if let saved = try? String(contentsOf: tokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), saved.count >= 32 {
            cachedToken = saved
            return saved
        }
        let fresh = Self.randomToken()
        save(fresh)
        return fresh
    }

    /// Новый токен — все сопряжённые iPhone теряют доступ.
    public func revokeAll() {
        lock.lock(); defer { lock.unlock() }
        save(Self.randomToken())
    }

    private func save(_ value: String) {
        try? FileManager.default.createDirectory(at: tokenURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? value.write(to: tokenURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
        cachedToken = value
    }

    /// Проверка заголовка «Authorization: Bearer …» без утечки по времени сравнения.
    public func isAuthorized(_ header: String?) -> Bool {
        guard let header, header.lowercased().hasPrefix("bearer ") else { return false }
        let offered = header.dropFirst("bearer ".count).trimmingCharacters(in: .whitespaces)
        return Self.constantTimeEqual(offered, token)
    }

    // MARK: - код сопряжения

    /// Новый шестизначный код. Прежний перестаёт действовать.
    @discardableResult
    public func newCode(validFor lifetime: TimeInterval = 300) -> (code: String, expires: Date) {
        lock.lock(); defer { lock.unlock() }
        let value = String(format: "%06d", Self.randomNumber(below: 1_000_000))
        let expires = now().addingTimeInterval(lifetime)
        code = (value, expires, 0)
        return (value, expires)
    }

    public var activeCode: (code: String, expires: Date)? {
        lock.lock(); defer { lock.unlock() }
        guard let code, code.expires > now() else { return nil }
        return (code.value, code.expires)
    }

    public func cancelCode() {
        lock.lock(); code = nil; lock.unlock()
    }

    public func pair(code offered: String) -> PairResult {
        let digits = offered.filter(\.isNumber)
        lock.lock()
        guard var current = code, current.expires > now() else {
            code = nil
            lock.unlock()
            return .expired
        }
        if Self.constantTimeEqual(digits, current.value) {
            code = nil                 // одноразовый
            lock.unlock()
            return .success(token: token)
        }
        current.attempts += 1
        code = current.attempts >= Self.maxAttempts ? nil : current
        lock.unlock()
        return current.attempts >= Self.maxAttempts ? .expired : .invalid
    }

    // MARK: - случайность

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func randomNumber(below limit: UInt32) -> UInt32 {
        var value: UInt32 = 0
        repeat {
            _ = withUnsafeMutableBytes(of: &value) { SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!) }
        } while value >= UInt32.max - (UInt32.max % limit)      // без смещения распределения
        return value % limit
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8), right = Array(b.utf8)
        var difference = UInt8(left.count == right.count ? 0 : 1)
        for index in 0..<max(left.count, right.count) {
            let x = index < left.count ? left[index] : 0
            let y = index < right.count ? right[index] : 0
            difference |= x ^ y
        }
        return difference == 0
    }
}
