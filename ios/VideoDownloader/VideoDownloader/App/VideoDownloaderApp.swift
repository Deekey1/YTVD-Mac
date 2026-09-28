import SwiftData
import SwiftUI
import UIKit

@main
struct VideoDownloaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(Connection.shared)
                .environment(TransferService.shared)
        }
        .modelContainer(Persistence.container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Prefs.register()
        // Подключаемся к фоновой сессии как можно раньше: система могла разбудить
        // приложение без окна только ради того, чтобы отдать скачанный файл.
        _ = TransferService.shared
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == TransferService.sessionIdentifier else {
            completionHandler()
            return
        }
        TransferService.shared.backgroundCompletion = completionHandler
    }
}

enum AppTab: Hashable {
    case download, library, settings
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Connection.self) private var connection
    @Environment(TransferService.self) private var transfers
    @State private var tab: AppTab = .download
    @State private var download = DownloadModel()
    @State private var restored = false

    var body: some View {
        TabView(selection: $tab) {
            DownloadView(model: download)
                .tabItem { Label("Скачать", systemImage: "arrow.down.circle") }
                .tag(AppTab.download)
            LibraryView()
                .tabItem { Label("Библиотека", systemImage: "film.stack") }
                .tag(AppTab.library)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .onOpenURL { url in
            if let link = SharedInbox.link(fromDeepLink: url) { accept(link) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: activate()
            case .background: transfers.stopPolling()
            default: break
            }
        }
        .task { activate() }
    }

    private func activate() {
        Task {
            await connection.check()
            await connection.rediscover()
            if !restored {
                restored = true
                await transfers.restore()
            } else {
                transfers.startPolling()
            }
        }
        // Ссылка из «Поделиться», если приложение не открылось само.
        if let link = SharedInbox.popAll().last { accept(link) }
        download.refreshClipboardHint()
    }

    private func accept(_ link: URL) {
        tab = .download
        download.text = link.absoluteString
        download.resolve(connection: connection)
    }
}
