import SwiftUI
import YTVDAPI

/// Настройки: какой Mac, сопряжение, качество по умолчанию, поведение загрузок.
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
            Form {
                Section {
                    ServerStatusRow()
                    if connection.serverURL != nil {
                        Button(connection.isPaired ? "Сопрячь заново" : "Ввести код сопряжения") { pairing = true }
                        Button("Проверить соединение") { Task { await connection.check() } }
                    }
                } header: {
                    Text("Mac")
                } footer: {
                    if connection.isPaired {
                        Text(connection.reachableAway
                             ? "Вне дома приложение само переключится на Tailscale — держите его на iPhone включённым (в приложении Tailscale: VPN On Demand)."
                             : "Чтобы качать вне дома, поставьте Tailscale на Mac и на iPhone под одной учётной записью.")
                    }
                }

                Section {
                    ForEach(browser.found) { found in
                        Button { select(found) } label: {
                            HStack {
                                Label(found.name, systemImage: "desktopcomputer")
                                Spacer()
                                if connecting == found.name {
                                    ProgressView()
                                } else if found.name == connection.serverName {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if browser.found.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(browser.problem ?? "Ищу Mac с YTVD в этой сети…").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Найдено в сети")
                } footer: {
                    Text("На Mac включите YTVD → Настройки → «Сервер для iPhone». Mac и iPhone должны быть в одной сети.")
                }

                Section {
                    TextField("192.168.1.10:8765", text: $manualAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(connectManually)
                    Button("Подключить", action: connectManually)
                        .disabled(manualAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Адрес вручную")
                } footer: {
                    Text("Если Mac не находится сам: адрес показан на Mac в настройках сервера.")
                }

                Section("Скачивание") {
                    Picker("Качество по умолчанию", selection: $defaultQuality) {
                        ForEach(DefaultQuality.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("Только по Wi-Fi", isOn: $wifiOnly)
                    Toggle("Сохранять в «Фото»", isOn: $autoSaveToPhotos)
                    Toggle("Оставлять копию на Mac", isOn: $keepOnMac)
                }

                Section {
                    NavigationLink("Сведения для отладки") { DebugInfoView() }
                    if connection.serverURL != nil {
                        Button("Забыть этот Mac", role: .destructive) { confirmForget = true }
                    }
                }
            }
            .navigationTitle("Настройки")
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
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.serverName ?? connection.serverURL?.host() ?? "Mac не выбран")
                    .font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if connection.status == .checking { ProgressView() }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch connection.status {
        case .online: "checkmark.circle.fill"
        case .checking: "circle.dotted"
        case .notConfigured: "desktopcomputer"
        case .unpaired: "lock.circle.fill"
        case .offline: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch connection.status {
        case .online: .green
        case .unpaired, .offline: .orange
        default: .secondary
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
            Form {
                Section {
                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onChange(of: code) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(6))
                            if digits != value { code = digits }
                            if digits.count == 6, !busy { submit() }
                        }
                } header: {
                    Text("Код с Mac")
                } footer: {
                    Text("На Mac: YTVD → Настройки → «Сервер для iPhone» → «Показать код». Код действует пять минут.")
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
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
