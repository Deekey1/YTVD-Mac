import Foundation
import Observation
import UIKit
import YTVDAPI

/// Выбранный Mac: адрес, токен сопряжения и доступность прямо сейчас.
@Observable @MainActor
final class Connection {

    enum Status: Equatable {
        case notConfigured
        case checking
        case online(ServerInfo)
        /// Mac отвечает, но этот iPhone ему не знаком — нужен код сопряжения.
        case unpaired
        case offline(String)
    }

    static let shared = Connection()

    private(set) var serverURL: URL?
    private(set) var serverName: String?
    private(set) var status: Status
    private var token: String?
    @ObservationIgnored private static let tokenAccount = "token"

    init() {
        let defaults = UserDefaults.standard
        let url = defaults.string(forKey: Prefs.serverURL).flatMap(URL.init(string:))
        let savedToken = Keychain.read(Self.tokenAccount)
        serverURL = url
        serverName = defaults.string(forKey: Prefs.serverName)
        token = savedToken
        status = url == nil ? .notConfigured : (savedToken == nil ? .unpaired : .checking)
    }

    var isPaired: Bool { token != nil }

    var info: ServerInfo? {
        if case .online(let info) = status { return info }
        return nil
    }

    var isOnline: Bool { info != nil }

    /// Клиент для запросов, которым нужен токен.
    func client() throws -> APIClient {
        guard let serverURL else { throw AppError.noServer }
        guard let token else { throw AppError.unauthorized }
        return APIClient(baseURL: serverURL, token: token)
    }

    /// Клиент для загрузки. Mac у приложения один, поэтому берём его текущий адрес:
    /// если роутер выдал Mac новый IP, начатые загрузки продолжатся по новому.
    func client(for server: URL) -> APIClient {
        APIClient(baseURL: serverURL ?? server, token: token)
    }

    // MARK: - проверка

    func check() async {
        guard let serverURL else {
            status = .notConfigured
            return
        }
        if !isOnline { status = .checking }
        do {
            let info = try await APIClient(baseURL: serverURL, token: token).info()
            if info.authorized {
                status = .online(info)
                if serverName != info.name { remember(name: info.name) }
            } else {
                status = .unpaired
            }
        } catch {
            status = .offline(AppError.from(error).localizedDescription)
        }
    }

    /// Mac не отвечает по старому адресу — ищем его по имени в Bonjour.
    func rediscover() async {
        guard case .offline = status, let name = serverName,
              let found = await ServerBrowser.find(named: name),
              let url = await ServerBrowser.bestURL(for: found), url != serverURL else { return }
        refreshAddress(url, name: name)
        await check()
    }

    // MARK: - выбор Mac

    /// Новый адрес. Токен от другого Mac сюда не отправляем — забываем его.
    func select(url: URL, name: String?) {
        let sameMac = (name != nil && name == serverName) || url.host() == serverURL?.host()
        if !sameMac { forgetToken() }
        serverURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Prefs.serverURL)
        if let name { remember(name: name) }
        status = token == nil ? .unpaired : .checking
    }

    /// Bonjour нашёл тот же Mac по новому адресу (роутер выдал другой IP) — токен остаётся.
    func refreshAddress(_ url: URL, name: String) {
        guard name == serverName, url != serverURL else { return }
        serverURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Prefs.serverURL)
    }

    func pair(code: String) async throws {
        guard let serverURL else { throw AppError.noServer }
        let response = try await APIClient(baseURL: serverURL, token: nil)
            .pair(code: code, deviceName: UIDevice.current.name)
        token = response.token
        Keychain.save(response.token, for: Self.tokenAccount)
        remember(name: response.serverName)
        await check()
    }

    func forgetServer() {
        forgetToken()
        serverURL = nil
        serverName = nil
        UserDefaults.standard.removeObject(forKey: Prefs.serverURL)
        UserDefaults.standard.removeObject(forKey: Prefs.serverName)
        status = .notConfigured
    }

    private func forgetToken() {
        token = nil
        Keychain.delete(Self.tokenAccount)
    }

    private func remember(name: String) {
        serverName = name
        UserDefaults.standard.set(name, forKey: Prefs.serverName)
    }
}
