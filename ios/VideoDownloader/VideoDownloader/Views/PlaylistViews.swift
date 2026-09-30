import SwiftData
import SwiftUI
import YTVDIcons

// Плейлисты: список, экран плейлиста, создание и «Добавить в плейлист».

/// Список плейлистов во вкладке «Библиотека».
struct PlaylistsList: View {
    let playlists: [Playlist]
    let items: [VideoItem]
    let onCreate: () -> Void
    let onOpen: (UUID) -> Void

    @Environment(\.modelContext) private var context
    @State private var renaming: Playlist?
    @State private var newName = ""
    @State private var pendingDelete: Playlist?

    private var byID: [UUID: VideoItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        List {
            Button(action: onCreate) { NewPlaylistRow() }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.bg)

            ForEach(playlists) { playlist in
                let videos = playlist.itemIDs.compactMap { byID[$0] }
                Button { onOpen(playlist.id) } label: {
                    PlaylistRow(playlist: playlist, videos: videos)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.bg)
                .contextMenu {
                    if !videos.isEmpty {
                        Button("Смотреть всё", systemImage: "play") { PlaybackController.shared.play(videos) }
                    }
                    Button("Переименовать", systemImage: "pencil") {
                        newName = playlist.name
                        renaming = playlist
                    }
                    Button("Удалить плейлист", systemImage: "trash", role: .destructive) { pendingDelete = playlist }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { pendingDelete = playlist } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            if playlists.isEmpty {
                EmptyState(icon: .playlist, title: "Плейлистов пока нет",
                           detail: "Соберите видео в нужном порядке — они будут играть подряд.")
                    .padding(.bottom, 80)
            }
        }
        .alert("Название плейлиста", isPresented: renamingShown) {
            TextField("Название", text: $newName)
            Button("Сохранить") { if let renaming { Playlists.rename(renaming, to: newName, in: context) } }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Удалить плейлист?", isPresented: deleteShown, titleVisibility: .visible,
                            presenting: pendingDelete) { playlist in
            Button("Удалить", role: .destructive) { Playlists.delete(playlist, in: context) }
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text("Видео останутся в библиотеке — удалится только список.")
        }
    }

    private var renamingShown: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}

/// Строка «Новый плейлист» — синий блок с плюсом.
struct NewPlaylistRow: View {
    var title = "Новый плейлист"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconView(.add, size: 20, lineWidth: 2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(BlockBackground(color: Theme.blue, radius: 8))
                Text(title).font(.system(.body, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, 10)
            Hairline()
        }
        .background(Theme.bg)
        .contentShape(Rectangle())
    }
}

/// Строка плейлиста: «пачка» обложек, название, сколько видео и сколько идёт.
struct PlaylistRow: View {
    enum Accessory { case chevron, add, added }

    let playlist: Playlist
    let videos: [VideoItem]
    var accessory: Accessory = .chevron

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    // Две «подложки» сзади — как стопка кассет.
                    RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                        .fill(Theme.bg3).frame(width: 96, height: 54).offset(x: 8, y: -8)
                    RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                        .fill(Theme.hair).frame(width: 96, height: 54).offset(x: 4, y: -4)
                    ThumbnailView(local: videos.first?.thumbnailURL, audioOnly: videos.first?.isAudioOnly ?? false)
                        .frame(width: 96, height: 54)
                }
                .frame(width: 106, height: 64, alignment: .bottomLeading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Text(subtitle).font(.caption).monospacedDigit().foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
                switch accessory {
                case .chevron:
                    IconView(.chevronRight, size: 14, lineWidth: 2).foregroundStyle(Theme.muted)
                case .add:
                    IconView(.add, size: 18, lineWidth: 2.2).foregroundStyle(Theme.blue)
                case .added:
                    IconView(.check, size: 16, lineWidth: 2.4).foregroundStyle(Theme.blue)
                        .accessibilityLabel("Уже в плейлисте")
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

    private var subtitle: String {
        let count = Fmt.plural(videos.count, "видео", "видео", "видео")
        let total = Playlists.totalDuration(of: videos)
        return total > 0 ? "\(count) · \(Fmt.duration(total))" : count
    }
}

/// Экран плейлиста: смотреть подряд, менять порядок, добавлять и убирать видео.
struct PlaylistDetailView: View {
    let playlistID: UUID
    @Query private var matches: [Playlist]
    @Query(sort: \VideoItem.downloadedAt, order: .reverse) private var allItems: [VideoItem]
    @Environment(\.modelContext) private var context
    @Environment(PlaybackPositions.self) private var positions
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var adding = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    /// Название в панели появляется, когда шапка с ним уехала вверх.
    @State private var titleInBar = false

    init(playlistID: UUID) {
        self.playlistID = playlistID
        _matches = Query(filter: #Predicate<Playlist> { $0.id == playlistID })
    }

    private var playlist: Playlist? { matches.first }

    private var videos: [VideoItem] {
        guard let playlist else { return [] }
        let byID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.itemIDs.compactMap { byID[$0] }
    }

    var body: some View {
        Group {
            if let playlist {
                content(playlist)
            } else {
                EmptyState(icon: .playlist, title: "Плейлист удалён", detail: "")
                    .frame(maxHeight: .infinity)
                    .background(Theme.bg)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ playlist: Playlist) -> some View {
        let videos = self.videos
        return List {
            // Шапка — обычная строка, а не заголовок секции: заголовок в простом списке
            // прилипает к верху и на длинном плейлисте занимал бы полэкрана.
            header(playlist, videos: videos)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.bg2)
            Section {
                ForEach(videos) { item in
                    Button { PlaybackController.shared.play(videos, startingWith: item.id) } label: {
                        VideoRow(item: item, progress: positions.progress(for: item.id),
                                 resume: positions.resumeTime(for: item.id))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.bg)
                }
                .onMove { source, destination in
                    playlist.move(fromOffsets: source, toOffset: destination)
                    try? context.save()
                }
                .onDelete { offsets in
                    // Видео уходит только из плейлиста — в библиотеке оно остаётся.
                    let ids = offsets.map { videos[$0].id }
                    ids.forEach(playlist.remove)
                    try? context.save()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .environment(\.editMode, $editMode)
        .modifier(ScrolledPast(distance: 44, isPast: $titleInBar))
        .overlay {
            if videos.isEmpty {
                EmptyState(icon: .playlist, title: "В плейлисте пусто",
                           detail: "Нажмите «Добавить», чтобы выбрать видео из библиотеки.")
                    .padding(.top, 140)
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(playlist.name)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .opacity(titleInBar ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: titleInBar)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button("Готово") { withAnimation { editMode = .inactive } }
                        .fontWeight(.semibold)
                } else {
                    menu(playlist, videos: videos)
                }
            }
        }
        .sheet(isPresented: $adding) {
            AddVideosSheet(playlist: playlist)
        }
        .alert("Название плейлиста", isPresented: $renaming) {
            TextField("Название", text: $newName)
            Button("Сохранить") { Playlists.rename(playlist, to: newName, in: context) }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Удалить плейлист?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                dismiss()
                Playlists.delete(playlist, in: context)
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Видео останутся в библиотеке — удалится только список.")
        }
    }

    private func menu(_ playlist: Playlist, videos: [VideoItem]) -> some View {
        Menu {
            Button("Изменить порядок", systemImage: "arrow.up.arrow.down") {
                withAnimation { editMode = .active }
            }
            .disabled(videos.count < 2)
            Button("Добавить видео", systemImage: "plus") { adding = true }
            Button("Переименовать", systemImage: "pencil") {
                newName = playlist.name
                renaming = true
            }
            Divider()
            Button("Удалить плейлист", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } label: {
            IconView(.menu, size: 20, lineWidth: 2).foregroundStyle(Theme.blue)
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .accessibilityLabel("Действия с плейлистом")
    }

    private func header(_ playlist: Playlist, videos: [VideoItem]) -> some View {
        let resumeID = positions.lastStarted(among: videos.map(\.id))
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(summary(videos)).font(.footnote).monospacedDigit().foregroundStyle(Theme.dim)
                }
                HStack(spacing: 10) {
                    // «Продолжить» — с того видео, которое смотрели последним, с того же места.
                    Button { PlaybackController.shared.play(videos, startingWith: resumeID) } label: {
                        HStack(spacing: 8) {
                            IconView(.playFill, size: 16)
                            Text(resumeID == nil ? "Смотреть всё" : "Продолжить")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 46))
                    .disabled(videos.isEmpty)
                    Button { adding = true } label: {
                        HStack(spacing: 6) {
                            IconView(.add, size: 16, lineWidth: 2.1)
                            Text("Добавить")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 46, expand: false))
                }
            }
            .padding(Theme.Metrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg2)
            GroupHeader(title: "Порядок", trailing: editMode.isEditing ? "перетаскивайте за ≡" : nil)
        }
    }

    private func summary(_ videos: [VideoItem]) -> String {
        let count = Fmt.plural(videos.count, "видео", "видео", "видео")
        let total = Playlists.totalDuration(of: videos)
        return total > 0 ? "\(count) · \(Fmt.duration(total))" : count
    }
}

// MARK: - выбор видео

/// Список видео с отметками. Порядок нажатий — это и порядок в плейлисте, номера видны сразу.
struct VideoPicker: View {
    let items: [VideoItem]
    @Binding var selection: [UUID]

    var body: some View {
        List {
            ForEach(items) { item in
                let number = selection.firstIndex(of: item.id).map { $0 + 1 }
                Button {
                    if let index = selection.firstIndex(of: item.id) {
                        selection.remove(at: index)
                    } else {
                        selection.append(item.id)
                    }
                } label: {
                    VideoRow(item: item, accessory: AnyView(SelectionMark(number: number)))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.bg)
                .accessibilityAddTraits(number != nil ? [.isSelected, .isButton] : .isButton)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
    }
}

/// Отметка выбора: пустой квадрат или синий с номером — в «блочном» стиле.
struct SelectionMark: View {
    let number: Int?

    var body: some View {
        ZStack {
            if let number {
                BlockBackground(color: Theme.blue, radius: 6)
                Text("\(number)").font(.system(.subheadline, weight: .bold)).monospacedDigit().foregroundStyle(.white)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.muted, lineWidth: 1.5)
            }
        }
        .frame(width: 28, height: 28)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityHidden(true)
    }
}

/// Новый плейлист: название и видео в нужном порядке.
struct PlaylistEditorView: View {
    var preselected: [UUID] = []
    var onCreated: ((Playlist) -> Void)?

    @Query(sort: \VideoItem.downloadedAt, order: .reverse) private var items: [VideoItem]
    @Query private var playlists: [Playlist]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selection: [UUID] = []
    @State private var prepared = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("НАЗВАНИЕ").font(Theme.Font.group).tracking(1.2).foregroundStyle(Theme.dim)
                    TextField("", text: $name,
                              prompt: Text(suggestedName).foregroundStyle(Theme.muted))
                        .submitLabel(.done)
                        .panelField()
                }
                .padding(Theme.Metrics.gutter)
                .background(Theme.bg2)
                Hairline()
                GroupHeader(title: "Видео", trailing: selection.isEmpty ? "по порядку нажатий"
                            : "выбрано: \(selection.count)")
                if items.isEmpty {
                    EmptyState(icon: .video, title: "Библиотека пуста",
                               detail: "Плейлист можно создать и пустым, а видео добавить позже.")
                    Spacer()
                } else {
                    VideoPicker(items: items, selection: $selection)
                }
                VStack(spacing: 0) {
                    Hairline()
                    Button(action: create) {
                        Text(selection.isEmpty ? "Создать пустой плейлист"
                             : "Создать · \(Fmt.plural(selection.count, "видео", "видео", "видео"))")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(Theme.Metrics.gutter)
                }
                .background(Theme.bg2)
            }
            .background(Theme.bg)
            .navigationTitle("Новый плейлист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .onAppear {
                guard !prepared else { return }
                prepared = true
                selection = preselected
            }
        }
    }

    private var suggestedName: String { Playlists.suggestedName(existing: playlists.map(\.name)) }

    private func create() {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let chosen = selection.compactMap { byID[$0] }
        let title = Playlists.cleanName(name).isEmpty ? suggestedName : name
        let playlist = Playlists.create(name: title, items: chosen, in: context)
        dismiss()
        onCreated?(playlist)
    }
}

/// «Добавить в плейлист» для одного видео из библиотеки.
struct AddToPlaylistSheet: View {
    let item: VideoItem
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @Query(sort: \VideoItem.downloadedAt, order: .reverse) private var items: [VideoItem]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false

    private var byID: [UUID: VideoItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            List {
                Button { creating = true } label: { NewPlaylistRow(title: "Новый плейлист…") }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.bg)

                ForEach(playlists) { playlist in
                    let contains = playlist.contains(item.id)
                    Button {
                        Playlists.add([item], to: playlist, in: context)
                        dismiss()
                    } label: {
                        PlaylistRow(playlist: playlist, videos: playlist.itemIDs.compactMap { byID[$0] },
                                    accessory: contains ? .added : .add)
                            .opacity(contains ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(contains)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.bg)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("В плейлист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .sheet(isPresented: $creating) {
                PlaylistEditorView(preselected: [item.id]) { _ in dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Добавить в плейлист несколько видео из библиотеки.
struct AddVideosSheet: View {
    let playlist: Playlist
    @Query(sort: \VideoItem.downloadedAt, order: .reverse) private var items: [VideoItem]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [UUID] = []

    private var candidates: [VideoItem] { items.filter { !playlist.contains($0.id) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if candidates.isEmpty {
                    EmptyState(icon: .check, title: "Добавлять нечего",
                               detail: "Все видео библиотеки уже в этом плейлисте.")
                    Spacer()
                } else {
                    GroupHeader(title: "Видео", trailing: selection.isEmpty ? "по порядку нажатий"
                                : "выбрано: \(selection.count)")
                    VideoPicker(items: candidates, selection: $selection)
                    VStack(spacing: 0) {
                        Hairline()
                        Button {
                            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                            Playlists.add(selection.compactMap { byID[$0] }, to: playlist, in: context)
                            dismiss()
                        } label: {
                            Text(selection.isEmpty ? "Добавить"
                                 : "Добавить · \(Fmt.plural(selection.count, "видео", "видео", "видео"))")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selection.isEmpty)
                        .padding(Theme.Metrics.gutter)
                    }
                    .background(Theme.bg2)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Добавить в «\(playlist.name)»")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
        }
    }
}
