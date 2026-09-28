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
    /// Все адреса этого Mac — в домашней сети и в Tailscale. Их сообщает сам Mac после
    /// сопряжения, поэтому вне дома приложение переключается на Tailscale без ввода адреса.
    private(set) var alternates: [URL]
    private(set) var status: Status
    private var token: String?
    @ObservationIgnored private static let tokenAccount = "token"

    init() {
        let defaults = UserDefaults.standard
        let url = defaults.string(forKey: Prefs.serverURL).flatMap(URL.init(string:))
        let savedToken = Keychain.read(Self.tokenAccount)
        serverURL = url
        serverName = defaults.string(forKey: Prefs.serverName)
        alternates = (defaults.stringArray(forKey: Prefs.serverAlternates) ?? []).compactMap(URL.init(string:))
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
        switch await Self.probe(Self.candidates(current: serverURL, alternates: alternates), token: token) {
        case .online(let url, let info):
            if url != self.serverURL { use(url) }
            status = .online(info)
            if serverName != info.name { remember(name: info.name) }
            if let list = info.addresses { remember(addresses: list) }
        case .unpaired:
            status = .unpaired
        case .offline(let message):
            status = .offline(message)
        }
    }

    enum ProbeResult {
        case online(URL, ServerInfo)
        case unpaired
        case offline(String)
    }

    /// Спрашивает все известные адреса Mac разом и берёт первый, где Mac узнал токен:
    /// дома быстрее ответит домашний адрес, в дороге — адрес в Tailscale.
    nonisolated static func probe(_ candidates: [URL], token: String?) async -> ProbeResult {
        await withTaskGroup(of: (URL, ServerInfo?, Error?).self) { group in
            for url in candidates {
                group.addTask {
                    do { return (url, try await APIClient(baseURL: url, token: token).info(), nil) }
                    catch { return (url, nil, error) }
                }
            }
            var reachedButUnknown = false
            var firstError: Error?
            for await (url, info, error) in group {
                if let info {
                    guard info.authorized else { reachedButUnknown = true; continue }
                    group.cancelAll()
                    return .online(url, info)
                }
                if firstError == nil { firstError = error }
            }
            if reachedButUnknown { return .unpaired }
            return .offline(AppError.from(firstError ?? AppError.serverUnavailable).localizedDescription)
        }
    }

    /// Текущий адрес первым, потом остальные известные — без повторов. Голые адреса
    /// Tailscale (100.x) пропускаем: обычный HTTP на них iOS не пускает, ходим по имени *.ts.net.
    nonisolated static func candidates(current: URL, alternates: [URL]) -> [URL] {
        var seen = Set<String>()
        return ([current] + alternates)
            .filter { !isTailnet($0.host() ?? "") }
            .filter { seen.insert($0.absoluteString).inserted }
    }

    // MARK: - маршрут

    /// Как сейчас идёт связь: «в домашней сети» или «через Tailscale».
    static func route(for url: URL?) -> String? {
        guard let host = url?.host() else { return nil }
        if isTailnet(host) || isTailnetName(host) { return "через Tailscale" }
        if isPrivateLAN(host) { return "в домашней сети" }
        return nil
    }

    /// 100.64.0.0/10 — адреса устройств в Tailscale.
    nonisolated static func isTailnet(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    /// Имя устройства в Tailscale (MagicDNS): macbook-pro.tail1234.ts.net.
    nonisolated static func isTailnetName(_ host: String) -> Bool {
        host.lowercased().hasSuffix(".ts.net")
    }

    nonisolated static func isPrivateLAN(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return host.hasSuffix(".local") }
        return parts[0] == 10 || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 172 && (16...31).contains(parts[1]))
    }

    /// Mac доступен и из дома, и через Tailscale — значит, качать можно откуда угодно.
    var reachableAway: Bool {
        alternates.contains { Self.isTailnetName($0.host() ?? "") }
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
            || alternates.contains { $0.host() == url.host() }
        if !sameMac {
            forgetToken()
            remember(addresses: [])
        }
        serverURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Prefs.serverURL)
        if let name { remember(name: name) }
        status = token == nil ? .unpaired : .checking
    }

    /// Bonjour нашёл тот же Mac по новому адресу (роутер выдал другой IP) — токен остаётся.
    func refreshAddress(_ url: URL, name: String) {
        guard name == serverName, url != serverURL else { return }
        use(url)
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
        remember(addresses: [])
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

    /// Переход на другой адрес того же Mac — например, на Tailscale вне дома.
    private func use(_ url: URL) {
        serverURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Prefs.serverURL)
    }

    private func remember(addresses: [String]) {
        alternates = addresses.compactMap(URL.init(string:))
        UserDefaults.standard.set(alternates.map(\.absoluteString), forKey: Prefs.serverAlternates)
    }

    private func remember(name: String) {
        serverName = name
        UserDefaults.standard.set(name, forKey: Prefs.serverName)
    }
}
