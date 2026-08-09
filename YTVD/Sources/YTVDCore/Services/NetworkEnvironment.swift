import Foundation
import SystemConfiguration

/// Через какой интерфейс сейчас уходит трафик. Нужно, чтобы подсказка про VPN
/// появлялась только тогда, когда VPN действительно включён.
public enum NetworkEnvironment {

    /// Имя основного сетевого интерфейса: en0, utun5…
    public static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "YTVD" as CFString, nil, nil),
              let info = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any]
        else { return nil }
        return info["PrimaryInterface"] as? String
    }

    /// Туннельные интерфейсы поднимают VPN-клиенты.
    public static func isTunnel(_ interface: String?) -> Bool {
        guard let interface else { return false }
        return ["utun", "ipsec", "ppp", "tun", "tap"].contains { interface.hasPrefix($0) }
    }

    public static var isUsingVPN: Bool { isTunnel(primaryInterface()) }
}
