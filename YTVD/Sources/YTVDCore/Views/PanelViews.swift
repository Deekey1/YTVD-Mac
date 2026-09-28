import AppKit
import SwiftUI

/// Общая рамка выдвижной панели.
private struct PanelChrome<Content: View, Footer: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    @Environment(\.ytvdSnapshot) private var snapshot

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(Theme.Font.group).tracking(1.1).foregroundStyle(Theme.dim)
                Spacer()
                IconButton(.close, help: "Закрыть ⎋", action: close)
            }
            .padding(.leading, 11)
            .padding(.trailing, 8)
            .frame(height: 30)
            .background(Theme.bg2)
            Hairline()

            Group {
                if snapshot {
                    // ImageRenderer не рисует содержимое ScrollView — в снимке разворачиваем список целиком.
                    VStack(spacing: 0) { content() }
                } else {
                    ScrollView { VStack(spacing: 0) { content() } }
                }
            }
            // Панель перекрывает окно целиком, иначе под ней просвечивает список вариантов.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Hairline()
            HStack(spacing: 8) { footer() }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.bg2)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.bg)
    }
}

/// Строка настройки: слева описание, справа управляющий элемент.
private struct SettingRow<Control: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12)).foregroundStyle(Theme.text)
                    if let note {
                        Text(note).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                control()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            Hairline()
        }
    }
}

/// Поле ввода, которое корректно попадает в офскрин-снимок.
private struct PanelField: View {
    @Binding var text: String
    var width: CGFloat = 150
    var alignment: TextAlignment = .leading

    @Environment(\.ytvdSnapshot) private var snapshot

    var body: some View {
        Group {
            if snapshot {
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity,
                           alignment: alignment == .trailing ? .trailing : .leading)
            } else {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .multilineTextAlignment(alignment)
            }
        }
        .padding(.horizontal, 7)
        .frame(width: width, height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hair, lineWidth: 1))
    }
}

/// Тумблер в том же «блочном» стиле, что и плашки.
struct BlockToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isOn ? Theme.blue : Theme.bg3)
                .frame(width: 34, height: 19)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.black.opacity(0.35), lineWidth: 1))
                .overlay(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isOn ? Color.white : Color(nsColor: NSColor(hex: "C8C8C9")))
                        .frame(width: 15, height: 15)
                        .padding(.horizontal, 2)
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                }
                .animation(.easeOut(duration: 0.16), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

/// Сегментированный переключатель качества.
private struct Segmented: View {
    @Binding var value: Int
    let options: [(label: String, value: Int)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button { value = option.value } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: value == option.value ? .semibold : .regular))
                        .foregroundStyle(value == option.value ? Color.white : Theme.dim)
                        .fixedSize()                       // подписи не должны обрезаться
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(value == option.value ? Theme.blue : Theme.bg2)
                }
                .buttonStyle(.plain)
                if index < options.count - 1 { Theme.sep.frame(width: 1, height: 24) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(Theme.hair, lineWidth: 1))
    }
}

// MARK: - настройки

struct SettingsPanel: View {
    /// Браузеры, из которых yt-dlp умеет брать cookies.
    /// Оформление окна: следом за системой либо принудительно.
    static let themes: [(String, String)] = [
        ("как в системе", "system"), ("светлое", "light"), ("тёмное", "dark"),
    ]

    static let browsers: [(String, String)] = [
        ("нет", ""), ("Chrome", "chrome"), ("Safari", "safari"), ("Firefox", "firefox"),
    ]

    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var server: ServerController

    init(model: AppModel) {
        self.model = model
        self.settings = model.settings
        self.server = model.server
    }

    var body: some View {
        PanelChrome(title: "Настройки", close: { model.panel = nil }) {
            SettingRow(title: "Папка сохранения", note: settings.directoryDisplayPath) {
                MiniButton(title: "Обзор…") { model.chooseDirectory() }
            }
            SettingRow(title: "Качество по умолчанию") {
                Segmented(value: Binding(get: { settings.defaultQuality },
                                         set: { settings.defaultQuality = $0 }),
                          options: [("720p", 720), ("1080p", 1080), ("2K", 1440),
                                    ("4K", 2160), ("Макс", 4320)])
            }
            SettingRow(title: "Всегда H.264 + AAC",
                       note: "Совместимо с Telegram, QuickTime, iPhone") {
                BlockToggle(isOn: Binding(get: { settings.alwaysH264 },
                                          set: { settings.alwaysH264 = $0 }))
            }
            SettingRow(title: "Анализировать ссылку из буфера",
                       note: "Как только она там появится") {
                BlockToggle(isOn: Binding(get: { settings.watchClipboard },
                                          set: { value in
                    settings.watchClipboard = value
                    value ? model.clipboard.start() : model.clipboard.stop()
                }))
            }
            SettingRow(title: "Скачивать сразу после анализа",
                       note: "Без подтверждения, в качестве по умолчанию") {
                BlockToggle(isOn: Binding(get: { settings.autoDownload },
                                          set: { settings.autoDownload = $0 }))
            }
            SettingRow(title: "Сохранять обложку рядом", note: "{имя}.jpg") {
                BlockToggle(isOn: Binding(get: { settings.saveCoverAlongside },
                                          set: { settings.saveCoverAlongside = $0 }))
            }
            SettingRow(title: "Поверх всех окон") {
                BlockToggle(isOn: Binding(get: { settings.floatOnTop },
                                          set: { settings.floatOnTop = $0 }))
            }
            SettingRow(title: "Запускать при входе в систему") {
                BlockToggle(isOn: Binding(get: { settings.launchAtLogin },
                                          set: { value in
                    settings.launchAtLogin = value
                    LoginItem.setEnabled(value)
                }))
            }
            SettingRow(title: "Оформление") {
                Segmented(value: Binding(
                    get: { Self.themes.firstIndex { $0.1 == settings.appearance } ?? 0 },
                    set: { settings.appearance = Self.themes[$0].1 }),
                          options: Self.themes.enumerated().map { ($0.element.0, $0.offset) })
            }
            SettingRow(title: "Шаблон имени файла", note: "{title} {quality} {source} {id} {date}") {
                PanelField(text: Binding(get: { settings.fileNameTemplate },
                                         set: { settings.fileNameTemplate = $0 }))
            }
            SettingRow(title: "Ограничить размер файла",
                       note: "Выберет качество, которое влезает в лимит") {
                HStack(spacing: 6) {
                    if settings.limitFileSize {
                        PanelField(text: Binding(
                            get: { String(settings.maxFileSizeMB) },
                            set: { settings.maxFileSizeMB = max(1, Int($0.filter(\.isNumber)) ?? 1) }),
                                   width: 54, alignment: .trailing)
                        Text("МБ").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    BlockToggle(isOn: Binding(get: { settings.limitFileSize },
                                              set: { settings.limitFileSize = $0 }))
                }
            }
            SettingRow(title: "Брать cookies из браузера",
                       note: "Помогает, когда площадка требует подтвердить вход") {
                Segmented(value: Binding(
                    get: { Self.browsers.firstIndex { $0.1 == settings.cookiesFromBrowser } ?? 0 },
                    set: { settings.cookiesFromBrowser = Self.browsers[$0].1 }),
                          options: Self.browsers.enumerated().map { ($0.element.0, $0.offset) })
            }
            SettingRow(title: "Прокси для загрузок",
                       note: "Мимо VPN: socks5://127.0.0.1:1080") {
                PanelField(text: Binding(get: { settings.proxyURL },
                                         set: { settings.proxyURL = $0 }))
            }
            SettingRow(title: "Сервер для iPhone", note: server.statusText) {
                BlockToggle(isOn: Binding(get: { settings.serverEnabled },
                                          set: { server.setEnabled($0, toolchain: model.toolchain) }))
            }
            if settings.serverEnabled {
                SettingRow(title: "Доступ к серверу",
                           note: settings.serverBind == "loopback"
                               ? "Только с этого Mac — для проверки"
                               : "Домашняя сеть и Tailscale, по коду сопряжения") {
                    Segmented(value: Binding(
                        get: { settings.serverBind == "loopback" ? 1 : 0 },
                        set: { server.setBind($0 == 1 ? "loopback" : "all", toolchain: model.toolchain) }),
                              options: [("Сеть", 0), ("Только Mac", 1)])
                }
                SettingRow(title: "Сопряжение с iPhone", note: server.pairingNote) {
                    if let code = server.codeText {
                        Text(code)
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                    } else if server.isRunning {
                        MiniButton(title: "Показать код") { server.showCode() }
                    }
                }
                SettingRow(title: "Не давать Mac засыпать", note: server.keepAwakeNote) {
                    BlockToggle(isOn: Binding(get: { settings.serverKeepAwake },
                                              set: { server.setKeepAwake($0) }))
                }
                SettingRow(title: "Отключить все iPhone", note: "Каждому понадобится новый код") {
                    MiniButton(title: "Отключить") { server.revokeAll() }
                }
            }
            SettingRow(title: "Движок", note: model.toolchain.summary) {
                MiniButton(title: "Проверить") {
                    Task { await model.refreshToolchain() }
                }
            }
            SettingRow(title: "Версия программы",
                       note: model.appUpdateNote ?? "YTVD \(AppUpdater.currentVersion)") {
                MiniButton(title: model.appUpdating ? "Обновляю…" : "Проверить обновления") {
                    model.checkForAppUpdate()
                }
            }
        } footer: {
            Text("YTVD \(AppUpdater.currentVersion)")
                .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            Spacer()
            MiniButton(title: "Сбросить") { settings.reset() }
        }
    }
}

// MARK: - история

struct HistoryPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var history: HistoryStore

    init(model: AppModel) {
        self.model = model
        self.history = model.history
    }

    var body: some View {
        PanelChrome(title: "История", close: { model.panel = nil }) {
            if history.entries.isEmpty {
                VStack(spacing: 6) {
                    IconView(.history, size: 22).foregroundStyle(Theme.muted)
                    Text("Пока пусто").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(history.entries) { entry in
                    HistoryRow(entry: entry)
                    Hairline()
                }
            }
        } footer: {
            Text("\(Fmt.plural(history.entries.count, "файл", "файла", "файлов")) · \(Fmt.bytes(history.totalBytes))")
                .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            Spacer()
            MiniButton(title: "Открыть папку") { model.openDownloadDirectory() }
            MiniButton(title: "Очистить") { history.clear() }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: "4A5462")),
                                              Color(nsColor: NSColor(hex: "22262B"))],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.4), lineWidth: 1))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.sourceColor(entry.source))
                        .frame(width: 7, height: 7)
                        .padding(3),
                    alignment: .topLeading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.system(size: 11.5)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(entry.quality) · \(Fmt.ago(entry.date))")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Fmt.bytes(entry.bytes))
                .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(hovering ? Theme.bg2 : Theme.bg)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard entry.fileExists else { return }
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        }
        .help(entry.fileExists ? entry.path : "Файл перемещён или удалён")
        .opacity(entry.fileExists ? 1 : 0.5)
    }
}

/// Автозапуск при входе в систему.
enum LoginItem {
    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppServiceShim.register()
            } else {
                try SMAppServiceShim.unregister()
            }
        } catch {
            NSLog("YTVD: автозапуск не удалось изменить — \(error.localizedDescription)")
        }
    }
}
