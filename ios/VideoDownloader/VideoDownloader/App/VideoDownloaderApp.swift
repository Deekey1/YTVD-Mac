import SwiftData
import SwiftUI
import UIKit
import YTVDIcons

@main
struct VideoDownloaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(Connection.shared)
                .environment(TransferService.shared)
                .environment(PlaybackPositions.shared)
                .tint(Theme.blue)
        }
        .modelContainer(Persistence.container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Prefs.register()
        Theme.applyAppearance()
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

    static let bar: [(tab: AppTab, icon: Icon, title: String)] = [
        (tab: .download, icon: .download, title: "Скачать"),
        (tab: .library, icon: .video, title: "Библиотека"),
        (tab: .settings, icon: .settings, title: "Настройки"),
    ]
}

private struct TabSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<AppTab>? = nil
}

extension EnvironmentValues {
    /// Какая вкладка выбрана — нужна панели, которая стоит внутри экранов.
    var tabSelection: Binding<AppTab>? {
        get { self[TabSelectionKey.self] }
        set { self[TabSelectionKey.self] = newValue }
    }
}

extension View {
    /// Своя нижняя панель. Ставится в корень экрана внутри NavigationStack и на вложенные
    /// экраны: отступ, заданный снаружи стека, до его содержимого не доходит.
    func ytvdTabBar() -> some View { modifier(TabBarModifier()) }
}

private struct TabBarModifier: ViewModifier {
    @Environment(\.tabSelection) private var selection

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let selection { BottomTabBar(selection: selection, items: AppTab.bar) }
            }
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Connection.self) private var connection
    @Environment(TransferService.self) private var transfers
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .download
    @State private var download = DownloadModel()
    @State private var restored = false

    var body: some View {
        // Системный TabView оставляем ради поведения (вкладка открывается, только когда
        // её выбрали), а панель рисуем свою — как иконки в шапке YTVD на Mac. Панель стоит
        // внутри каждой вкладки: отступ снизу от внешнего safeAreaInset до вкладок не доходит.
        TabView(selection: $tab) {
            DownloadView(model: download)
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.download)
            LibraryView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.library)
            SettingsView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.settings)
        }
        .environment(\.tabSelection, $tab)
        .background(Theme.bg.ignoresSafeArea())
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
                #if DEBUG
                if DemoData.isEnabled {
                    connection.showDemoOnline()
                    DemoData.seed(context)
                    download.showDemo(DemoData.video)
                    transfers.injectDemo(DemoData.transfer)
                }
                #endif
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
        download.accept(link, connection: connection)
    }
}
