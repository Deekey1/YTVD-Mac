import SwiftUI
import UIKit
import YTVDAPI

/// Сведения для отладки: версии, адрес сервера, место. Токен здесь не показывается.
struct DebugInfoView: View {
    @Environment(Connection.self) private var connection
    @Environment(TransferService.self) private var transfers
    @State private var updating = false
    @State private var updateResult: String?

    var body: some View {
        List {
            Section("Приложение") {
                LabeledContent("Версия", value: appVersion)
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
                LabeledContent("Устройство", value: UIDevice.current.model)
                LabeledContent("Свободно на iPhone", value: LibraryFiles.freeSpace.map(Fmt.bytes) ?? "—")
                LabeledContent("Загрузок в работе", value: "\(transfers.active.count)")
            }

            Section("Сервер") {
                LabeledContent("Состояние", value: statusText)
                LabeledContent("Адрес", value: connection.serverURL?.absoluteString ?? "—")
                LabeledContent("Сопряжение", value: connection.isPaired ? "есть" : "нет")
                if let info = connection.info {
                    LabeledContent("YTVD на Mac", value: info.appVersion == "0" ? "из исходников" : info.appVersion)
                    LabeledContent("Версия API", value: info.apiVersion)
                    LabeledContent("yt-dlp", value: info.ytdlpVersion ?? "—")
                    LabeledContent("FFmpeg", value: info.ffmpegVersion ?? "—")
                    LabeledContent("JavaScript", value: info.jsRuntime ?? "не найден")
                    LabeledContent("Свободно на Mac", value: info.freeSpace.map(Fmt.bytes) ?? "—")
                }
            }

            if !connection.alternates.isEmpty {
                Section("Адреса Mac") {
                    ForEach(connection.alternates, id: \.self) { url in
                        LabeledContent(url.absoluteString,
                                       value: Connection.route(for: url) ?? "")
                    }
                }
            }

            if connection.isOnline {
                Section {
                    Button {
                        updateEngine()
                    } label: {
                        HStack {
                            Text("Обновить движок на Mac")
                            Spacer()
                            if updating { ProgressView() }
                        }
                    }
                    .disabled(updating)
                } footer: {
                    Text(updateResult ?? "YouTube регулярно меняется. Если скачивание перестало работать, обновите yt-dlp на Mac — само приложение на iPhone для этого не меняется.")
                }
            }
        }
        .navigationTitle("Отладка")
        .refreshable { await connection.check() }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var statusText: String {
        switch connection.status {
        case .online: "подключено"
        case .checking: "проверка…"
        case .notConfigured: "Mac не выбран"
        case .unpaired: "нужно сопряжение"
        case .offline(let message): message
        }
    }

    private func updateEngine() {
        updating = true
        updateResult = "Mac скачивает свежий yt-dlp…"
        Task {
            defer { updating = false }
            do {
                let result = try await connection.client().updateEngine()
                updateResult = result.message
                await connection.check()
            } catch {
                updateResult = AppError.from(error).localizedDescription
            }
        }
    }
}
