import Foundation
import Network
import Observation
import YTVDAPI

/// Поиск Mac с YTVD в локальной сети через Bonjour — чтобы не вводить IP руками.
@Observable @MainActor
final class ServerBrowser {

    struct Found: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        /// Адреса в домашней сети и порт, которые Mac сам объявил в Bonjour.
        var addresses: [String] = []
        var port: Int?
        var id: String { name }
    }

    private(set) var found: [Found] = []
    private(set) var problem: String?
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: API.bonjourType, domain: nil), using: parameters)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let list = results.compactMap { result -> Found? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                var found = Found(name: name, endpoint: result.endpoint)
                if case .bonjour(let txt) = result.metadata {
                    found.addresses = (txt["ip"] ?? "").split(separator: ",").map(String.init)
                    found.port = txt["port"].flatMap { Int($0) }
                }
                return found
            }
            .sorted { $0.name < $1.name }
            Task { @MainActor in self?.found = list }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.update(state) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Найти Mac по имени — например, когда роутер выдал ему новый адрес.
    static func find(named name: String, timeout: TimeInterval = 4) async -> Found? {
        let browser = ServerBrowser()
        browser.start()
        defer { browser.stop() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let found = browser.found.first(where: { $0.name == name }) { return found }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }

    private func update(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            problem = nil
        case .waiting(let error):
            problem = Self.describe(error)
        case .failed(let error):
            problem = Self.describe(error)
            stop()
        default:
            break
        }
    }

    static func describe(_ error: NWError) -> String {
        // kDNSServiceErr_PolicyDenied: пользователь не дал доступ к локальной сети.
        if case .dns(let code) = error, code == -65570 {
            return "Нет доступа к локальной сети — включите его: Настройки → VideoDownloader → Локальная сеть"
        }
        return "Поиск Mac не работает: \(error.localizedDescription)"
    }

    // MARK: - адрес найденного Mac

    /// Сначала адреса, которые Mac объявил сам, — они из домашней сети. Если ни один
    /// не ответил, подключаемся по имени сервиса: так найдётся Mac и без этих подсказок.
    nonisolated static func bestURL(for found: Found) async -> URL? {
        if let port = found.port {
            for address in found.addresses {
                guard let url = URL(string: "http://\(address):\(port)") else { continue }
                if (try? await APIClient(baseURL: url, token: nil).info()) != nil { return url }
            }
        }
        return await resolve(found.endpoint)
    }

    /// Подключаемся к сервису по имени и смотрим, куда попали: так получаем обычный IPv4-адрес,
    /// который годится для URL и не зависит от того, как роутер назвал Mac.
    nonisolated static func resolve(_ endpoint: NWEndpoint, timeout: TimeInterval = 6) async -> URL? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let gate = OneShot<URL?>()

        return await withCheckedContinuation { continuation in
            gate.arm(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.finish(Self.httpURL(connection.currentPath?.remoteEndpoint))
                    connection.cancel()
                case .failed, .cancelled:
                    gate.finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                gate.finish(nil)
                connection.cancel()
            }
        }
    }

    nonisolated static func httpURL(_ endpoint: NWEndpoint?) -> URL? {
        guard case .hostPort(let host, let port)? = endpoint else { return nil }
        let text: String
        switch host {
        case .ipv4(let address):
            text = "\(address)".components(separatedBy: "%")[0]
        case .ipv6(let address):
            text = "[\("\(address)".components(separatedBy: "%")[0])]"
        case .name(let name, _):
            text = name
        @unknown default:
            return nil
        }
        return URL(string: "http://\(text):\(port.rawValue)")
    }
}

/// Продолжение, которое можно завершить из нескольких мест — сработает только первое.
final class OneShot<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    func arm(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func finish(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
