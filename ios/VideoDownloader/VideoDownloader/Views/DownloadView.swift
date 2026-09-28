import SwiftData
import SwiftUI
import YTVDAPI

/// Главный экран: ссылка, превью, качество, загрузки.
struct DownloadView: View {
    @Bindable var model: DownloadModel
    @Environment(Connection.self) private var connection
    @Environment(TransferService.self) private var transfers
    @Environment(\.modelContext) private var context
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                ConnectionBanner()

                Section {
                    TextField("Вставьте ссылку на видео", text: $model.text, axis: .vertical)
                        .lineLimit(1...3)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($fieldFocused)
                        .onSubmit(resolve)
                    HStack(spacing: 12) {
                        PasteButton(supportedContentTypes: [.url, .plainText]) { providers in
                            model.paste(providers, connection: connection)
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        Spacer()
                        Button("Загрузить", action: resolve)
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .disabled(!model.canResolve)
                    }
                } footer: {
                    if model.clipboardHasLink, model.text.isEmpty {
                        Text("В буфере обмена есть ссылка — нажмите «Вставить».")
                    }
                }

                switch model.state {
                case .idle:
                    EmptyView()
                case .resolving:
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Mac разбирает ссылку…").foregroundStyle(.secondary)
                        }
                    }
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                case .ready(let video):
                    VideoPreviewSections(video: video, selection: $model.selectedFormatId,
                                         isStarting: model.isStarting) {
                        model.download(context: context, transfers: transfers)
                    }
                }

                if !transfers.transfers.isEmpty {
                    Section("Загрузки") {
                        ForEach(transfers.transfers) { transfer in
                            TransferRow(transfer: transfer)
                        }
                    }
                }
            }
            .navigationTitle("Скачать")
            .toolbar {
                if model.state != .idle {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Очистить") { model.clear() }
                    }
                }
            }
            .confirmationDialog("Видео уже находится в библиотеке", isPresented: duplicateShown,
                                titleVisibility: .visible, presenting: model.duplicate) { duplicate in
                Button("Смотреть") { PlaybackController.shared.play(duplicate.existing) }
                Button("Скачать в другом качестве") {
                    model.start(video: duplicate.video, format: duplicate.format, replacing: nil, transfers: transfers)
                }
                Button("Заменить", role: .destructive) {
                    model.start(video: duplicate.video, format: duplicate.format,
                                replacing: duplicate.existing.id, transfers: transfers)
                }
                Button("Отмена", role: .cancel) {}
            } message: { duplicate in
                Text("Уже скачано: \(duplicate.existing.summary). Сейчас выбрано: \(duplicate.format.label).")
            }
            .alert("Не получилось", isPresented: alertShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alert ?? "")
            }
        }
    }

    private func resolve() {
        fieldFocused = false
        model.resolve(connection: connection)
    }

    private var duplicateShown: Binding<Bool> {
        Binding(get: { model.duplicate != nil }, set: { if !$0 { model.duplicate = nil } })
    }

    private var alertShown: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }
}

/// Подсказка, если Mac не выбран, не сопряжён или недоступен.
struct ConnectionBanner: View {
    @Environment(Connection.self) private var connection

    var body: some View {
        switch connection.status {
        case .online, .checking:
            EmptyView()
        case .notConfigured:
            banner("Выберите Mac в настройках", detail: "На Mac: YTVD → Настройки → «Сервер для iPhone».",
                   symbol: "desktopcomputer")
        case .unpaired:
            banner("Нужно сопряжение с Mac", detail: "Введите код с Mac во вкладке «Настройки».",
                   symbol: "lock")
        case .offline(let message):
            banner("Mac недоступен", detail: message, symbol: "wifi.exclamationmark")
        }
    }

    private func banner(_ title: String, detail: String, symbol: String) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol).foregroundStyle(.orange)
            }
        }
    }
}

/// Превью ролика и выбор качества.
struct VideoPreviewSections: View {
    let video: VideoInfo
    @Binding var selection: String?
    let isStarting: Bool
    let onDownload: () -> Void

    private var selected: VideoFormat? { video.formats.first { $0.id == selection } }

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                ThumbnailView(remote: video.thumbnail)
                    .frame(width: 128, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title).font(.headline).lineLimit(3)
                    if let channel = video.channel {
                        Text(channel).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let duration = video.duration, duration > 0 {
                        Text(Fmt.duration(duration))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }

        Section {
            ForEach(video.formats) { format in
                Button { selection = format.id } label: {
                    FormatRow(format: format, isSelected: format.id == selection,
                              isRecommended: format.id == video.recommendedFormatId)
                }
                .buttonStyle(.plain)
            }
            DisclosureGroup("Подробности") {
                ForEach(video.formats) { format in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(format.label) — \(format.codecTitle), \(format.container.uppercased())")
                            .font(.footnote.weight(.medium))
                        if let details = format.details {
                            Text(details).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .font(.subheadline)
        } header: {
            Text("Качество")
        } footer: {
            if selected?.needsTranscode == true {
                Text("Выше 1080p YouTube отдаёт только VP9 или AV1 — Mac перекодирует видео в HEVC. Это дольше, чем просто скачать.")
            }
        }

        Section {
            Button(action: onDownload) {
                HStack {
                    Spacer()
                    if isStarting {
                        ProgressView()
                    } else {
                        Label("Скачать", systemImage: "arrow.down.circle.fill").font(.headline)
                    }
                    Spacer()
                }
            }
            .disabled(selection == nil || isStarting)
        }
    }
}

struct FormatRow: View {
    let format: VideoFormat
    let isSelected: Bool
    let isRecommended: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(format.displayTitle).font(.body.weight(isSelected ? .semibold : .regular))
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let size = format.sizeText {
                Text(size).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var note: String? {
        if format.needsTranscode { return "перекодирование на Mac" }
        if isRecommended { return "рекомендуется" }
        return nil
    }
}
