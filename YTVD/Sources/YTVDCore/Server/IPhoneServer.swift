import Foundation
import SystemConfiguration

/// Сервер для iPhone в сборе: настоящий движок, очередь заданий, сопряжение и сеть.
/// Им пользуются и Mac-приложение, и режим `--serve` без интерфейса.
public final class IPhoneServer: @unchecked Sendable {

    public static var defaultDirectory: URL { JobStore.Configuration.standard.directory }

    public let backend: BackendServer
    private let box: ToolchainBox

    /// Движок обновился через API — Mac-приложению тоже стоит перечитать инструменты.
    public var onToolchainChange: (@Sendable (Toolchain) -> Void)?

    public init(toolchain: Toolchain, appVersion: String, name: String = IPhoneServer.computerName,
                directory: URL = IPhoneServer.defaultDirectory, maxConcurrent: Int = 1) {
        let box = ToolchainBox(toolchain)
        self.box = box
        // Сетевые настройки (cookies, прокси) читаем на каждое задание: их меняют в окне YTVD.
        let makeEngine: @Sendable () -> any MediaEngine = {
            YtDlpEngine(toolchain: box.current, network: AppSettings.storedNetwork())
        }
        let store = JobStore(config: .init(directory: directory, maxConcurrent: maxConcurrent),
                             makeEngine: makeEngine)
        let pairing = PairingManager(directory: directory)
        backend = BackendServer(store: store, pairing: pairing, name: name, appVersion: appVersion,
                                engineProbe: makeEngine,
                                freeSpace: { JobStore.availableSpace(directory) })
        backend.engineUpdate = { [weak self] in try await self?.updateEngine() ?? .upToDate(nil) }
    }

    public var toolchain: Toolchain { box.current }

    /// Mac-приложение обновило или нашло инструменты — новые задания пойдут уже с ними.
    public func use(_ toolchain: Toolchain) { box.current = toolchain }

    public func start(port: UInt16, bind: BindAddress) throws {
        if bind == .loopback {
            backend.addressProvider = { ["127.0.0.1"] }
        } else {
            // Сначала домашний адрес, потом имя в Tailscale (по нему ходит iPhone), потом сам адрес 100.x.
            backend.addressProvider = {
                IPhoneServer.localAddresses() + IPhoneServer.tailnetNames() + IPhoneServer.tailnetAddresses()
            }
        }
        try backend.start(port: port, bind: bind,
                          addresses: bind == .loopback ? [] : Self.localAddresses())
    }

    public func stop() { backend.stop() }

    // MARK: - обновление движка

    /// Тот же механизм, что у кнопки в окне YTVD: официальный выпуск yt-dlp с GitHub,
    /// проверка, что он запускается. iPhone только просит — исполняемый код живёт на Mac.
    func updateEngine() async throws -> EngineUpdateResult {
        let current = box.current.ytdlpVersion
        let latest = try await EngineUpdater.latestYtDlpVersion()
        guard EngineUpdater.isNewer(latest, than: current) else { return .upToDate(current) }
        try await EngineUpdater.installYtDlp()
        let chain = await Toolchain.discover()
        box.current = chain
        onToolchainChange?(chain)
        return EngineUpdateResult(updated: true, version: chain.ytdlpVersion,
                                  message: "Движок обновлён до версии \(chain.ytdlpVersion ?? latest)")
    }

    // MARK: - адреса

    /// Имя Mac, как в «Общий доступ» системных настроек. Его видит iPhone в списке серверов.
    public static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? Host.current().localizedName ?? "Mac"
    }

    /// Адреса этого Mac в Tailscale (100.64.0.0/10 на интерфейсе туннеля): по ним
    /// iPhone достаёт Mac из любой сети, если Tailscale включён на обоих.
    public static func tailnetAddresses() -> [String] {
        interfaceAddresses().filter { $0.name.hasPrefix("utun") && isTailnet($0.address) }.map(\.address)
    }

    /// Имена этого Mac в Tailscale (MagicDNS), вида macbook-pro.tail1234.ts.net.
    /// iPhone ходит по имени, а не по адресу 100.x: обычный HTTP на такие адреса iOS не пускает,
    /// а для *.ts.net в приложении есть узкое исключение.
    public static func tailnetNames() -> [String] {
        tailnetAddresses().compactMap(tailnetName(for:))
    }

    private static let namesLock = NSLock()
    nonisolated(unsafe) private static var names: [String: String] = [:]

    /// Обратный запрос к DNS Tailscale; ответ запоминаем — имя устройства не меняется.
    static func tailnetName(for address: String) -> String? {
        namesLock.lock()
        if let cached = names[address] { namesLock.unlock(); return cached }
        namesLock.unlock()

        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, address, &socketAddress.sin_addr) == 1 else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = withUnsafePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count),
                            nil, 0, NI_NAMEREQD)
            }
        }
        guard status == 0 else { return nil }
        let name = String(cString: host).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard isTailnetName(name) else { return nil }
        namesLock.lock(); names[address] = name; namesLock.unlock()
        return name
    }

    public static func isTailnetName(_ host: String) -> Bool {
        host.lowercased().hasSuffix(".ts.net")
    }

    /// 100.64.0.0/10 — диапазон, из которого Tailscale раздаёт адреса устройствам.
    public static func isTailnet(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }

    /// IPv4-адреса этого Mac в локальных сетях: их можно ввести на iPhone вручную.
    public static func localAddresses() -> [String] {
        interfaceAddresses()
            // Туннели VPN (utun) и служебные мосты iPhone всё равно не видит.
            .filter { $0.name.hasPrefix("en") || $0.name.hasPrefix("bridge") }
            .filter { !$0.address.hasPrefix("169.254.") }        // самоназначенный — связи нет
            // en0 — обычно Wi-Fi или основной порт: показываем его первым.
            .sorted { $0.name < $1.name }
            .map(\.address)
    }

    /// Все IPv4-адреса поднятых интерфейсов, кроме петли.
    private static func interfaceAddresses() -> [(name: String, address: String)] {
        var result: [(name: String, address: String)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            result.append((String(cString: entry.ifa_name), String(cString: host)))
        }
        return result
    }
}

/// Инструменты, общие для всех заданий. Обновление движка подменяет их на лету.
final class ToolchainBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Toolchain
    init(_ value: Toolchain) { self.value = value }
    var current: Toolchain {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}
