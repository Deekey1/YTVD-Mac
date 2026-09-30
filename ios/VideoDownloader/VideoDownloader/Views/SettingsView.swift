import SwiftUI
import YTVDAPI
import YTVDIcons

/// Настройки: какой Mac, сопряжение, качество по умолчанию, поведение загрузок.
/// Устроены как панель настроек YTVD на Mac: строки с описанием слева и переключателем справа.
struct SettingsView: View {
    @Environment(Connection.self) private var connection
    @State private var browser = ServerBrowser()
    @State private var manualAddress = ""
    @State private var connecting: String?
    @State private var pairing = false
    @State private var problem: String?
    @State private var confirmForget = false
    @AppStorage(Prefs.defaultQuality) private var defaultQuality = DefaultQuality.p1080.rawValue
    @AppStorage(Prefs.wifiOnly) private var wifiOnly = false
    @AppStorage(Prefs.autoSaveToPhotos) private var autoSaveToPhotos = false
    @AppStorage(Prefs.keepOnMac) private var keepOnMac = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Настройки")
                ScrollView {
                    VStack(spacing: 0) {
                        macSection
                        foundSection
                        manualSection
                        downloadSection
                        otherSection
                    }
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .ytvdTabBar()
            .navigationDestination(for: String.self) { _ in DebugInfoView().ytvdTabBar() }
            .onAppear { browser.start() }
            .onDisappear { browser.stop() }
            .sheet(isPresented: $pairing) { PairingView() }
            .alert("Не получилось подключиться", isPresented: problemShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
            .confirmationDialog("Забыть этот Mac?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Забыть", role: .destructive) { connection.forgetServer() }
            } message: {
                Text("Чтобы снова качать через него, понадобится новый код сопряжения.")
            }
        }
    }

    // MARK: - разделы

    private var macSection: some View {
        VStack(spacing: 0) {
            GroupHeader(title: "Mac")
            ServerStatusRow()
            if connection.serverURL != nil {
                HStack(spacing: 8) {
                    Button(connection.isPaired ? "Сопрячь заново" : "Ввести код сопряжения") { pairing = true }
                        .buttonStyle(MiniButtonStyle())
                    Button("Проверить соединение") { Task { await connection.check() } }
                        .buttonStyle(MiniButtonStyle())
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Metrics.gutter)
                .padding(.vertical, 10)
                .background(Theme.bg)
                Hairline()
            }
            if connection.isPaired {
                note(connection.reachableAway
                     ? "Вне дома приложение само переключится на Tailscale — держите его на iPhone включённым (в приложении Tailscale: VPN On Demand)."
                     : "Чтобы качать вне дома, поставьте Tailscale на Mac и на iPhone под одной учётной записью.")
            }
        }
    }

    private var foundSection: some View {
        VStack(spacing: 0) {
            GroupHeader(title: "Найдено в сети", trailing: browser.found.isEmpty ? nil : "\(browser.found.count)")
            ForEach(browser.found) { found in
                Button { select(found) } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            IconView(.tv, size: 20, lineWidth: 1.8).foregroundStyle(Theme.dim)
                            Text(found.name).font(.body).foregroundStyle(Theme.text)
                            Spacer()
                            if connecting == found.name {
                                ProgressView().tint(Theme.dim)
                            } else if found.name == connection.serverName {
                                IconView(.check, size: 16, lineWidth: 2.4).foregroundStyle(Theme.blue)
                                    .accessibilityLabel("Выбран")
                            }
                        }
                        .padding(.horizontal, Theme.Metrics.gutter)
                        .frame(minHeight: 50)
                        Hairline()
                    }
                    .background(Theme.bg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if browser.found.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.dim)
                        Text(browser.problem ?? "Ищу Mac с YTVD в этой сети…")
                            .font(.subheadline).foregroundStyle(Theme.dim)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Metrics.gutter)
                    .frame(minHeight: 50)
                    Hairline()
                }
                .background(Theme.bg)
            }
            note("На Mac включите YTVD → Настройки → «Сервер для iPhone». Mac и iPhone должны быть в одной сети.")
        }
    }

    private var manualSection: some View {
        VStack(spacing: 0) {
            GroupHeader(title: "Адрес вручную")
            HStack(spacing: 8) {
                TextField("", text: $manualAddress,
                          prompt: Text("192.168.1.10:8765").foregroundStyle(Theme.muted))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(connectManually)
                    .panelField()
                Button("Подключить", action: connectManually)
                    .buttonStyle(MiniButtonStyle())
                    .disabled(manualAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Theme.Metrics.gutter)
            .background(Theme.bg)
            Hairline()
            note("Если Mac не находится сам: адрес показан на Mac в настройках сервера. Вне дома — имя вида mac.tail….ts.net.")
        }
    }

    private var downloadSection: some View {
        VStack(spacing: 0) {
            GroupHeader(title: "Скачивание")
            SettingRow(title: "Качество по умолчанию", note: "Выбирается заранее, можно поменять перед загрузкой") {
                Menu {
                    Picker("Качество по умолчанию", selection: $defaultQuality) {
                        ForEach(DefaultQuality.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(DefaultQuality(rawValue: defaultQuality)?.title ?? "")
                            .font(.system(.subheadline, weight: .semibold))
                        IconView(.chevronDown, size: 12, lineWidth: 2)
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.bg2))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hair, lineWidth: 1))
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
            SettingRow(title: "Только по Wi-Fi", note: "По сотовой сети файлы не забираются") {
                BlockToggle(isOn: $wifiOnly, label: "Только по Wi-Fi")
            }
            SettingRow(title: "Сохранять в «Фото»", note: "Каждое скачанное видео — ещё и в медиатеку") {
                BlockToggle(isOn: $autoSaveToPhotos, label: "Сохранять в «Фото»")
            }
            SettingRow(title: "Оставлять копию на Mac", note: "Иначе Mac удаляет файл, как только iPhone его забрал") {
                BlockToggle(isOn: $keepOnMac, label: "Оставлять копию на Mac")
            }
        }
    }

    private var otherSection: some View {
        VStack(spacing: 0) {
            GroupHeader(title: "Прочее")
            NavigationLink(value: "debug") {
                VStack(spacing: 0) {
                    HStack {
                        Text("Сведения для отладки").font(.body).foregroundStyle(Theme.text)
                        Spacer()
                        IconView(.chevronRight, size: 13, lineWidth: 2).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, Theme.Metrics.gutter)
                    .frame(minHeight: 50)
                    Hairline()
                }
                .background(Theme.bg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if connection.serverURL != nil {
                Button { confirmForget = true } label: {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Забыть этот Mac").font(.body).foregroundStyle(Theme.red)
                            Spacer()
                        }
                        .padding(.horizontal, Theme.Metrics.gutter)
                        .frame(minHeight: 50)
                        Hairline()
                    }
                    .background(Theme.bg)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func note(_ text: String) -> some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Metrics.gutter)
                .padding(.vertical, 9)
            Hairline()
        }
        .background(Theme.lane)
    }

    // MARK: - действия

    private func select(_ found: ServerBrowser.Found) {
        connecting = found.name
        Task {
            defer { connecting = nil }
            guard let url = await ServerBrowser.bestURL(for: found) else {
                problem = "Не удалось узнать адрес «\(found.name)». Попробуйте ввести его вручную."
                return
            }
            connection.select(url: url, name: found.name)
            await connection.check()
            if connection.status == .unpaired { pairing = true }
        }
    }

    private func connectManually() {
        guard let url = APIClient.normalize(manualAddress) else {
            problem = "Адрес выглядит неправильно. Пример: 192.168.1.10:8765"
            return
        }
        connecting = url.host()
        Task {
            defer { connecting = nil }
            connection.select(url: url, name: nil)
            await connection.check()
            switch connection.status {
            case .unpaired: pairing = true
            case .offline(let message): problem = message
            default: manualAddress = ""
            }
        }
    }

    private var problemShown: Binding<Bool> {
        Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
    }
}

/// Строка состояния: к какому Mac подключены и отвечает ли он.
struct ServerStatusRow: View {
    @Environment(Connection.self) private var connection

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconView(.tv, size: 26, lineWidth: 1.7)
                    .foregroundStyle(Theme.dim)
                    .overlay(alignment: .bottomTrailing) {
                        Swatch(color: color, size: 10).offset(x: 3, y: 3)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.serverName ?? connection.serverURL?.host() ?? "Mac не выбран")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(detail).font(.footnote).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if connection.status == .checking { ProgressView().tint(Theme.dim) }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, 12)
            Hairline()
        }
        .background(Theme.bg)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch connection.status {
        case .online: Theme.green
        case .unpaired, .offline: Theme.orange
        default: Theme.steel
        }
    }

    private var detail: String {
        switch connection.status {
        case .online(let info):
            // «Подключено через Tailscale · YTVD 1.3 · 100.118.111.42:8765»
            var parts = ["Подключено" + (Connection.route(for: connection.serverURL).map { " \($0)" } ?? "")]
            // «0» — сборка YTVD без номера версии (запуск из исходников): его не показываем.
            if info.appVersion != "0" { parts.append("YTVD \(info.appVersion)") }
            if let url = connection.serverURL { parts.append("\(url.host() ?? ""):\(url.port ?? 0)") }
            return parts.joined(separator: " · ")
        case .checking: return "Проверяю…"
        case .notConfigured: return "Выберите Mac ниже или введите адрес"
        case .unpaired: return "Нужен код сопряжения с Mac"
        case .offline(let message): return message
        }
    }
}

/// Ввод шестизначного кода, который показывает Mac.
struct PairingView: View {
    @Environment(Connection.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GroupHeader(title: "Код с Mac")
                VStack(spacing: 12) {
                    TextField("", text: $code, prompt: Text("000 000").foregroundStyle(Theme.muted))
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .panelField()
                        .onChange(of: code) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(6))
                            if digits != value { code = digits }
                            if digits.count == 6, !busy { submit() }
                        }
                    Text("На Mac: YTVD → Настройки → «Сервер для iPhone» → «Показать код». Код действует пять минут.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Metrics.gutter)
                .background(Theme.bg)
                Hairline()
                if let error {
                    WarningBanner(title: "Не получилось", detail: error)
                }
                Spacer()
            }
            .background(Theme.bg)
            .navigationTitle(connection.serverName ?? "Сопряжение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Готово", action: submit).disabled(code.count != 6)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await connection.pair(code: code)
                dismiss()
            } catch {
                self.error = AppError.from(error).localizedDescription
                code = ""
            }
        }
    }
}
