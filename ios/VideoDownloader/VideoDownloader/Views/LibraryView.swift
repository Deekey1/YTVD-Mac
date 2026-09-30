import SwiftData
import SwiftUI
import YTVDAPI
import YTVDIcons

enum LibraryFilter: Hashable {
    case all, favorites, playlists
}

/// Скачанные видео, избранное и плейлисты. Всё — с диска телефона: работает и без сети.
struct LibraryView: View {
    @Query(sort: \VideoItem.downloadedAt, order: .reverse) private var items: [VideoItem]
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @Environment(\.modelContext) private var context
    @Environment(PlaybackPositions.self) private var positions

    @State private var filter: LibraryFilter = .all
    @State private var search = ""
    @State private var searching = false
    @State private var path = NavigationPath()
    @State private var info: VideoItem?
    @State private var pendingDelete: VideoItem?
    @State private var addingToPlaylist: VideoItem?
    @State private var creatingPlaylist = false
    @State private var notice: String?
    @FocusState private var searchFocused: Bool

    private var shown: [VideoItem] {
        let base = filter == .favorites ? items.filter(\.isFavorite) : items
        guard !search.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || ($0.channel ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScreenHeader(title: "Библиотека") {
                    if filter == .playlists {
                        IconToolButton(icon: .add, label: "Новый плейлист") { creatingPlaylist = true }
                    } else {
                        IconToolButton(icon: .search, active: searching, label: "Поиск") {
                            searching.toggle()
                            if searching { searchFocused = true } else { search = "" }
                        }
                    }
                }
                VStack(spacing: 0) {
                    Segmented(value: $filter, options: [("Все", .all), ("Избранное", .favorites),
                                                        ("Плейлисты", .playlists)], expand: true)
                        .padding(Theme.Metrics.gutter)
                    if searching, filter != .playlists { searchField }
                    Hairline()
                }
                .background(Theme.bg2)

                if filter == .playlists {
                    PlaylistsList(playlists: playlists, items: items,
                                  onCreate: { creatingPlaylist = true },
                                  onOpen: { path.append($0) })
                } else {
                    videoList
                }
                footer
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .ytvdTabBar()
            .navigationDestination(for: UUID.self) { PlaylistDetailView(playlistID: $0).ytvdTabBar() }
            .sheet(item: $info) { VideoInfoView(item: $0) }
            .sheet(item: $addingToPlaylist) { AddToPlaylistSheet(item: $0) }
            .sheet(isPresented: $creatingPlaylist) {
                PlaylistEditorView { path.append($0.id) }
            }
            .confirmationDialog("Удалить видео?", isPresented: deleteShown, titleVisibility: .visible,
                                presenting: pendingDelete) { item in
                Button("Удалить", role: .destructive) { Library.delete(item, in: context) }
                Button("Отмена", role: .cancel) {}
            } message: { item in
                Text("«\(item.title)» будет удалено с iPhone вместе с обложкой и из всех плейлистов.")
            }
            .alert(notice ?? "", isPresented: noticeShown) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            IconView(.search, size: 17, lineWidth: 1.9).foregroundStyle(Theme.muted)
            TextField("", text: $search, prompt: Text("Название или канал").foregroundStyle(Theme.muted))
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    IconView(.close, size: 14, lineWidth: 2).foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Стереть запрос")
            }
        }
        .panelField()
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.bottom, Theme.Metrics.gutter)
    }

    // MARK: - видео

    private var videoList: some View {
        List {
            ForEach(shown) { item in
                Button { PlaybackController.shared.play(item) } label: {
                    VideoRow(item: item, progress: positions.progress(for: item.id),
                             resume: positions.resumeTime(for: item.id))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.bg)
                .contextMenu { menu(for: item) }
                .swipeActions(edge: .leading) {
                    Button { Library.setFavorite(item, !item.isFavorite, in: context) } label: {
                        Label(item.isFavorite ? "Убрать" : "В избранное",
                              systemImage: item.isFavorite ? "star.slash" : "star")
                    }
                    .tint(Theme.orange)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { pendingDelete = item } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                    Button { addingToPlaylist = item } label: {
                        Label("В плейлист", systemImage: "text.badge.plus")
                    }
                    .tint(Theme.blue)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .overlay {
            if items.isEmpty {
                EmptyState(icon: .video, title: "Библиотека пуста",
                           detail: "Скачанные видео появятся здесь и будут доступны без интернета.")
            } else if !search.isEmpty, shown.isEmpty {
                EmptyState(icon: .search, title: "Ничего не нашлось",
                           detail: "По запросу «\(search)» видео нет.")
            } else if filter == .favorites, shown.isEmpty {
                EmptyState(icon: .star, title: "В избранном пусто",
                           detail: "Смахните видео вправо или удержите его и выберите «В избранное».")
            }
        }
    }

    @ViewBuilder
    private func menu(for item: VideoItem) -> some View {
        if let resume = positions.resumeTime(for: item.id) {
            Button("Продолжить с \(Fmt.duration(resume))", systemImage: "play") {
                PlaybackController.shared.play(item)
            }
            Button("Смотреть сначала", systemImage: "backward.end") {
                PlaybackController.shared.play(item, fromStart: true)
            }
        } else {
            Button("Смотреть", systemImage: "play") { PlaybackController.shared.play(item) }
        }
        Button(item.isFavorite ? "Убрать из избранного" : "В избранное",
               systemImage: item.isFavorite ? "star.slash" : "star") {
            Library.setFavorite(item, !item.isFavorite, in: context)
        }
        Button("Добавить в плейлист…", systemImage: "text.badge.plus") { addingToPlaylist = item }
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

    // MARK: - подвал

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack {
                Text(footerText).font(.footnote).monospacedDigit().foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .frame(minHeight: 34)
            .background(Theme.bg2)
        }
        // Строка состояния, как внизу окна на Mac: крупнее AX1 ей расти незачем.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// «5 видео · 1,98 ГБ», как «5 файлов · 1,98 ГБ» в истории на Mac.
    private var footerText: String {
        if filter == .playlists {
            return Fmt.plural(playlists.count, "плейлист", "плейлиста", "плейлистов")
        }
        let list = shown
        let bytes = list.reduce(Int64(0)) { $0 + $1.fileSize }
        return "\(list.count) видео · \(Fmt.bytes(bytes))"
    }

    // MARK: - вспомогательное

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

/// Строка видео — как строка истории на Mac, только с настоящей обложкой.
struct VideoRow: View {
    let item: VideoItem
    var progress: Double?
    var resume: Double?
    /// Номер в плейлисте или отметка выбора — справа.
    var accessory: AnyView?

    @Environment(\.dynamicTypeSize) private var typeSize

    private var large: Bool { typeSize.isAccessibilitySize }

    private var star: some View {
        IconView(.starFill, size: 16).foregroundStyle(Theme.orange)
            .accessibilityLabel("В избранном")
    }

    var body: some View {
        let layout = large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                layout {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Swatch(color: Theme.sourceColor(Theme.source(item.platform)), size: 8)
                            Text(meta).font(.caption).monospacedDigit().foregroundStyle(Theme.dim)
                                .lineLimit(1)
                            // При крупном шрифте звезда — в строке, чтобы обложка шла на всю ширину.
                            if large, accessory == nil, item.isFavorite { star }
                        }
                        if let resume {
                            Text("Остановились на \(Fmt.duration(resume))")
                                .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(Theme.blue)
                        } else {
                            Text(item.downloadedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        if !item.fileExists {
                            HStack(spacing: 4) {
                                IconView(.warningTriangle, size: 12, lineWidth: 2)
                                Text("Файл не найден")
                            }
                            .font(.caption).foregroundStyle(Theme.red)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let accessory {
                    accessory
                } else if item.isFavorite, !large {
                    star
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, 10)
            Hairline()
        }
        .background(Theme.bg)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let view = ThumbnailView(local: item.thumbnailURL, duration: item.duration, progress: progress,
                                 audioOnly: item.isAudioOnly)
        if typeSize.isAccessibilitySize {
            // Крупный шрифт — обложка на всю ширину над текстом.
            view.aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: .infinity)
        } else {
            view.frame(width: 118, height: 118 * 9 / 16)
        }
    }

    /// «1080p60 · 483 МБ»
    private var meta: String {
        [item.isAudioOnly ? "Звук" : item.formatLabel, Fmt.bytes(item.fileSize)].joined(separator: " · ")
    }
}

/// «Информация»: всё, что известно о файле, — строками, как в настройках Mac.
struct VideoInfoView: View {
    let item: VideoItem
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackPositions.self) private var positions

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ThumbnailView(local: item.thumbnailURL, platform: item.platform, duration: item.duration,
                                  progress: positions.progress(for: item.id), audioOnly: item.isAudioOnly)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .padding(Theme.Metrics.gutter)
                        .background(Theme.bg2)
                    Hairline()
                    GroupHeader(title: "Видео")
                    row("Название", item.title)
                    if let channel = item.channel { row("Канал", channel) }
                    if let duration = item.duration { row("Длительность", Fmt.duration(duration)) }
                    if let resume = positions.resumeTime(for: item.id) {
                        row("Остановились на", Fmt.duration(resume))
                    }
                    row("Избранное", item.isFavorite ? "да" : "нет")
                    GroupHeader(title: "Файл")
                    row("Качество", item.isAudioOnly ? "Только звук" : item.formatLabel)
                    if let resolution = item.resolutionText { row("Кадр", resolution) }
                    row("Кодек", codecTitle)
                    row("Размер", Fmt.bytes(item.fileSize))
                    row("Скачано", item.downloadedAt.formatted(date: .long, time: .shortened))
                    row("Имя на диске", item.fileName, mono: true)
                    GroupHeader(title: "Источник")
                    row("Площадка", Theme.source(item.platform).title)
                    if let url = URL(string: item.sourceURL) {
                        HStack {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    IconView(.externalLink, size: 15, lineWidth: 2)
                                    Text("Открыть оригинал")
                                }
                            }
                            .buttonStyle(MiniButtonStyle())
                            Spacer()
                        }
                        .padding(Theme.Metrics.gutter)
                        .background(Theme.bg)
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle("Информация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }

    private func row(_ title: String, _ value: String, mono: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.subheadline).foregroundStyle(Theme.dim)
                Spacer(minLength: 12)
                Text(value)
                    .font(mono ? .caption.monospaced() : .subheadline)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, 11)
            Hairline()
        }
        .background(Theme.bg)
        .accessibilityElement(children: .combine)
    }

    private var codecTitle: String {
        switch item.codec.lowercased() {
        case "h264": "H.264 + AAC"
        case "hevc": "HEVC + AAC"
        case "aac": "AAC"
        default: item.codec.uppercased()
        }
    }
}
