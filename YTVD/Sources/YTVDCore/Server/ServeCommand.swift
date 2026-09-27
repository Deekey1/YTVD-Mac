import Foundation

/// `YTVD --serve [--port 8765] [--bind 0.0.0.0|127.0.0.1|адрес]` — сервер для iPhone без окна.
///
/// Удобен для проверки через curl и для Mac, на котором окно YTVD не нужно.
/// Enter в терминале выдаёт новый код сопряжения.
public enum ServeCommand {

    /// Держим сервер живым до конца процесса.
    nonisolated(unsafe) private static var server: IPhoneServer?

    public static func run(arguments: [String]) -> Never {
        let port = value(after: "--port", in: arguments).flatMap(UInt16.init) ?? API.defaultPort
        let bind = BindAddress(value(after: "--bind", in: arguments) ?? "all")

        Task.detached {
            let chain = await Toolchain.discover()
            guard chain.isReady else {
                print("✗ yt-dlp не найден — установите: brew install yt-dlp")
                exit(1)
            }
            print("движок: \(chain.summary)")

            let instance = IPhoneServer(toolchain: chain, appVersion: AppUpdater.currentVersion)
            instance.backend.onStateChange = { state in
                switch state {
                case .listening(let actual):
                    print("сервер «\(instance.backend.name)» слушает порт \(actual)")
                    if bind == .loopback {
                        print("  http://127.0.0.1:\(actual)\(API.basePath)/info  (только этот Mac)")
                    } else {
                        for address in IPhoneServer.localAddresses() {
                            print("  http://\(address):\(actual)\(API.basePath)/info")
                        }
                    }
                    printCode(instance)
                case .failed(let reason):
                    print("✗ сервер не запустился: \(reason)")
                    exit(1)
                default:
                    break
                }
            }
            do {
                try instance.start(port: port, bind: bind)
            } catch {
                print("✗ сервер не запустился: \(error.localizedDescription)")
                exit(1)
            }
            server = instance

            FileHandle.standardInput.readabilityHandler = { handle in
                if handle.availableData.isEmpty {
                    handle.readabilityHandler = nil       // stdin закрыт — работаем дальше молча
                } else {
                    printCode(instance)
                }
            }
        }
        dispatchMain()
    }

    private static func printCode(_ server: IPhoneServer) {
        let (code, _) = server.backend.pairing.newCode(validFor: 600)
        print("код сопряжения для iPhone: \(code.prefix(3)) \(code.suffix(3))  (10 минут; Enter — новый)")
    }

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
