import Foundation
import IOKit.pwr_mgt
import SwiftUI

/// Сервер для iPhone внутри Mac-приложения: включение, адреса, код сопряжения.
@MainActor
public final class ServerController: ObservableObject {

    public enum Status: Equatable {
        case off
        case starting
        case running(port: UInt16)
        case failed(String)
    }

    @Published public private(set) var status: Status = .off
    @Published public private(set) var addresses: [String] = []
    /// Адреса в Tailscale — по ним iPhone достаёт Mac из любой сети.
    @Published public private(set) var remoteAddresses: [String] = []
    @Published public private(set) var code: String?
    /// Сколько секунд живёт показанный код — тикает раз в секунду.
    @Published public private(set) var codeSecondsLeft = 0
    /// Имя iPhone, который только что ввёл код.
    @Published public private(set) var lastPaired: String?

    /// Движок обновили с iPhone — окну YTVD тоже надо перечитать инструменты.
    var onToolchainChange: ((Toolchain) -> Void)?

    private let settings: AppSettings
    /// Где сервер хранит токен и задания. В тестах — временный каталог, чтобы не трогать настоящий токен.
    private let directory: URL
    private var server: IPhoneServer?
    private var codeExpires: Date?
    private var timer: Timer?
    private var sleepAssertion: IOPMAssertionID = 0

    public static let codeLifetime: TimeInterval = 300

    init(settings: AppSettings, directory: URL = IPhoneServer.defaultDirectory) {
        self.settings = settings
        self.directory = directory
    }

    // MARK: - включение

    /// Запускает или останавливает сервер по настройкам. Зовётся при старте и после смены настроек.
    func apply(toolchain: Toolchain) {
        guard settings.serverEnabled, toolchain.isReady else {
            stop()
            return
        }
        if let server {
            server.use(toolchain)
            return
        }
        start(toolchain: toolchain)
    }

    func setEnabled(_ enabled: Bool, toolchain: Toolchain) {
        settings.serverEnabled = enabled
        stop()
        apply(toolchain: toolchain)
    }

    /// Доступ из сети или только с этого Mac. Меняется на лету — сервер перезапускается.
    func setBind(_ bind: String, toolchain: Toolchain) {
        settings.serverBind = bind
        guard server != nil else { return }
        stop()
        apply(toolchain: toolchain)
    }

    private func start(toolchain: Toolchain) {
        let instance = IPhoneServer(toolchain: toolchain, appVersion: AppUpdater.currentVersion, directory: directory)
        instance.backend.onStateChange = { [weak self] state in
            Task { @MainActor in self?.update(state) }
        }
        instance.backend.onPaired = { [weak self] device in
            Task { @MainActor in
                self?.lastPaired = device
                self?.hideCode()
            }
        }
        instance.onToolchainChange = { [weak self] chain in
            Task { @MainActor in self?.onToolchainChange?(chain) }
        }
        let port = UInt16(clamping: settings.serverPort > 0 ? settings.serverPort : Int(API.defaultPort))
        do {
            status = .starting
            try instance.start(port: port, bind: BindAddress(settings.serverBind))
            server = instance
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        server?.stop()
        server = nil
        status = .off
        addresses = []
        remoteAddresses = []
        hideCode()
        updateSleepAssertion()
    }

    /// Переключатель «Не давать Mac засыпать».
    func setKeepAwake(_ keepAwake: Bool) {
        settings.serverKeepAwake = keepAwake
        updateSleepAssertion()
    }

    /// Пока сервер работает, Mac не засыпает сам (экран гаснет как обычно):
    /// спящий Mac iPhone издалека не разбудит.
    private func updateSleepAssertion() {
        let wanted = isRunning && settings.serverKeepAwake
        if wanted, sleepAssertion == 0 {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "YTVD: сервер для iPhone" as CFString, &id)
            if result == kIOReturnSuccess { sleepAssertion = id }
        } else if !wanted, sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }

    /// Держит ли сейчас Mac от сна — для тестов и подписи в настройках.
    var preventsSleep: Bool { sleepAssertion != 0 }

    private func update(_ state: HTTPServer.State) {
        switch state {
        case .listening(let port):
            status = .running(port: port)
            let loopback = BindAddress(settings.serverBind) == .loopback
            addresses = loopback ? ["127.0.0.1"] : IPhoneServer.localAddresses()
            remoteAddresses = loopback ? [] : IPhoneServer.tailnetAddresses()
            // Имя в Tailscale узнаём в фоне: это запрос к DNS, окно ждать его не должно.
            if !loopback {
                Task { [weak self] in
                    let names = await Task.detached { IPhoneServer.tailnetNames() }.value
                    guard !names.isEmpty else { return }
                    self?.remoteAddresses = names
                }
            }
        case .failed(let reason):
            status = .failed(reason)
            server = nil
        case .starting:
            status = .starting
        case .stopped:
            if server == nil { status = .off }
        }
        updateSleepAssertion()
    }

    // MARK: - сопряжение

    public func showCode() {
        guard let server else { return }
        lastPaired = nil
        let (value, expires) = server.backend.pairing.newCode(validFor: Self.codeLifetime)
        code = value
        codeExpires = expires
        tick()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let codeExpires, let server else { hideCode(); return }
        // Код гаснет и когда истёк, и когда iPhone им уже воспользовался.
        guard server.backend.pairing.activeCode?.code == code else { hideCode(); return }
        codeSecondsLeft = max(0, Int(codeExpires.timeIntervalSinceNow.rounded(.up)))
        if codeSecondsLeft == 0 { hideCode() }
    }

    public func hideCode() {
        timer?.invalidate()
        timer = nil
        server?.backend.pairing.cancelCode()
        code = nil
        codeExpires = nil
        codeSecondsLeft = 0
    }

    /// Все сопряжённые iPhone теряют доступ: у сервера новый токен.
    public func revokeAll() {
        guard let server else { return }
        server.backend.pairing.revokeAll()
        lastPaired = nil
        hideCode()
    }

    // MARK: - для интерфейса

    public var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    public var statusText: String {
        switch status {
        case .off:
            return "Выключен"
        case .starting:
            return "Запускается…"
        case .running(let port):
            guard let first = addresses.first else { return "Работает на порту \(port) — нет сети" }
            let rest = addresses.count > 1 ? " и ещё \(addresses.count - 1)" : ""
            let remote = remoteAddresses.first.map { " · вне дома через Tailscale: \($0)" } ?? ""
            return "Работает: \(first):\(port)\(rest)\(remote)"
        case .failed(let reason):
            return "Не запустился: \(reason)"
        }
    }

    public var codeText: String? {
        guard let code else { return nil }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    public var countdownText: String {
        String(format: "%d:%02d", codeSecondsLeft / 60, codeSecondsLeft % 60)
    }

    public var pairingNote: String {
        if code != nil { return "Введите код в приложении на iPhone · ещё \(countdownText)" }
        if let lastPaired { return "Подключён: \(lastPaired)" }
        return isRunning ? "Покажите код и введите его на iPhone" : "Сначала включите сервер"
    }

    /// Подпись под «Не давать Mac засыпать».
    public var keepAwakeNote: String {
        remoteAddresses.isEmpty
            ? "Пока сервер включён. Для доступа не из дома поставьте Tailscale на Mac и iPhone"
            : "Пока сервер включён — спящий Mac iPhone издалека не разбудит"
    }

    /// Для снимков окна: сервер «работает» и показывает код, ничего не открывая в сети.
    func setPreviewForTesting(port: UInt16, addresses: [String], code: String?,
                              remoteAddresses: [String] = []) {
        status = .running(port: port)
        self.addresses = addresses
        self.remoteAddresses = remoteAddresses
        self.code = code
        codeSecondsLeft = code == nil ? 0 : 272
    }
}
