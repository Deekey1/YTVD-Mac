import Foundation
import ServiceManagement

/// Регистрация приложения в списке автозапуска.
@available(macOS 13.0, *)
enum SMAppServiceShim {
    static func register() throws {
        guard SMAppService.mainApp.status != .enabled else { return }
        try SMAppService.mainApp.register()
    }

    static func unregister() throws {
        guard SMAppService.mainApp.status == .enabled else { return }
        try SMAppService.mainApp.unregister()
    }
}
