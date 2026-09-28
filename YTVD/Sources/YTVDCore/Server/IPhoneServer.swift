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

    /// IPv4-адреса этого Mac в локальных сетях: их можно ввести на iPhone вручную.
    public static func localAddresses() -> [String] {
        var result: [(name: String, address: String)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            // Туннели VPN (utun) и служебные мосты iPhone всё равно не видит.
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            if text.hasPrefix("169.254.") { continue }          // самоназначенный — связи нет
            result.append((name, text))
        }
        // en0 — обычно Wi-Fi или основной порт: показываем его первым.
        return result.sorted { $0.name < $1.name }.map(\.address)
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
