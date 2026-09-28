import SwiftData
import SwiftUI

/// Скачанные видео. Всё — с диска телефона: работает и без сети.
struct LibraryView: View {
    @Query(sort: \VideoItem.downloadedAt, order: .reverse) private var items: [VideoItem]
    @Environment(\.modelContext) private var context
    @State private var search = ""
    @State private var info: VideoItem?
    @State private var pendingDelete: VideoItem?
    @State private var notice: String?

    private var filtered: [VideoItem] {
        guard !search.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || ($0.channel ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { item in
                    Button { PlaybackController.shared.play(item) } label: {
                        VideoRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(for: item) }
                    .swipeActions {
                        Button("Удалить", systemImage: "trash", role: .destructive) { pendingDelete = item }
                    }
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Библиотека пуста", systemImage: "film.stack",
                                           description: Text("Скачанные видео появятся здесь и будут доступны без интернета."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Название или канал")
            .navigationTitle("Библиотека")
            .sheet(item: $info) { VideoInfoView(item: $0) }
            .confirmationDialog("Удалить видео?", isPresented: deleteShown, titleVisibility: .visible,
                                presenting: pendingDelete) { item in
                Button("Удалить", role: .destructive) { Library.delete(item, in: context) }
                Button("Отмена", role: .cancel) {}
            } message: { item in
                Text("«\(item.title)» будет удалено с iPhone вместе с обложкой.")
            }
            .alert(notice ?? "", isPresented: noticeShown) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func menu(for item: VideoItem) -> some View {
        Button("Смотреть", systemImage: "play") { PlaybackController.shared.play(item) }
        ShareLink(item: SharedMediaFile(source: item.fileURL, name: item.shareFileName),
                  preview: sharePreview(for: item)) {
            Label("Поделиться", systemImage: "square.and.arrow.up")
        }
        if !item.isAudioOnly {
            Button("Сохранить в «Фото»", systemImage: "photo.on.rectangle") { saveToPhotos(item) }
        }
        Button("Информация", systemImage: "info.circle") { info = item }
        Divider()
        Button("Удалить", systemImage: "trash", role: .destructive) { pendingDelete = item }
    }

    /// Обложка в шапке меню «Поделиться» — чтобы было видно, что именно отправляется.
    private func sharePreview(for item: VideoItem) -> SharePreview<Image, Never> {
        let thumbnail = item.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) }
        return SharePreview(item.title, image: thumbnail.map(Image.init(uiImage:)) ?? Image(systemName: "film"))
    }

    private func saveToPhotos(_ item: VideoItem) {
        Task {
            do {
                try await PhotosSaver.save(item.fileURL)
                notice = "Сохранено в «Фото»"
            } catch {
                notice = AppError.from(error).localizedDescription
            }
        }
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }
}

struct VideoRow: View {
    let item: VideoItem

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(local: item.thumbnailURL)
                .frame(width: 112, height: 63)
                .overlay(alignment: .bottomTrailing) {
                    if item.isAudioOnly {
                        Image(systemName: "waveform")
                            .font(.caption2.weight(.bold))
                            .padding(4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(item.summary).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(item.downloadedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
                if !item.fileExists {
                    Label("Файл не найден", systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// «Информация»: всё, что известно о файле.
struct VideoInfoView: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ThumbnailView(local: item.thumbnailURL)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    LabeledContent("Название") { Text(item.title).multilineTextAlignment(.trailing) }
                    if let channel = item.channel { LabeledContent("Канал", value: channel) }
                    if let duration = item.duration { LabeledContent("Длительность", value: Fmt.duration(duration)) }
                }
                Section("Файл") {
                    LabeledContent("Качество", value: item.isAudioOnly ? "Только звук" : item.formatLabel)
                    if let resolution = item.resolutionText { LabeledContent("Кадр", value: resolution) }
                    LabeledContent("Кодек", value: codecTitle)
                    LabeledContent("Размер", value: Fmt.bytes(item.fileSize))
                    LabeledContent("Скачано", value: item.downloadedAt.formatted(date: .long, time: .shortened))
                    LabeledContent("Имя на диске") { Text(item.fileName).font(.caption.monospaced()) }
                }
                Section("Источник") {
                    LabeledContent("Площадка", value: platformTitle)
                    if let url = URL(string: item.sourceURL) {
                        Link(destination: url) {
                            Label("Открыть оригинал", systemImage: "safari")
                        }
                    }
                }
            }
            .navigationTitle("Информация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }

    private var codecTitle: String {
        switch item.codec.lowercased() {
        case "h264": "H.264 + AAC"
        case "hevc": "HEVC + AAC"
        case "aac": "AAC"
        default: item.codec.uppercased()
        }
    }

    private var platformTitle: String {
        switch item.platform {
        case "youtube": "YouTube"
        case "vimeo": "Vimeo"
        case "rutube": "Rutube"
        case "vk": "VK Видео"
        default: "Другая"
        }
    }
}
