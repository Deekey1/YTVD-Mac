import Foundation
import SwiftData

/// Плейлист: название и видео в выбранном порядке.
///
/// Порядок храним списком идентификаторов VideoItem: отношения «многие ко многим»
/// в SwiftData порядка не держат. Видео, удалённое из библиотеки, из списка убирается.
@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var itemIDs: [UUID] = []

    init(id: UUID = UUID(), name: String, itemIDs: [UUID] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.itemIDs = Playlist.unique(itemIDs)
        self.createdAt = createdAt
    }

    func contains(_ id: UUID) -> Bool { itemIDs.contains(id) }

    /// Добавляет в конец то, чего ещё нет.
    func append(_ ids: [UUID]) { itemIDs = Playlist.unique(itemIDs + ids) }

    func remove(_ id: UUID) { itemIDs.removeAll { $0 == id } }

    func remove(atOffsets offsets: IndexSet) {
        itemIDs = itemIDs.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// Перестановка — с теми же смыслами индексов, что у onMove в SwiftUI.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { itemIDs[$0] }
        var rest = itemIDs.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: max(0, min(insertAt, rest.count)))
        itemIDs = rest
    }

    /// Без повторов, в прежнем порядке.
    static func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}

/// Операции с плейлистами. Сохраняем сразу: список должен пережить закрытие приложения.
@MainActor
enum Playlists {

    /// Видео плейлиста в его порядке; то, чего уже нет в библиотеке, пропускаем.
    static func items(of playlist: Playlist, in context: ModelContext) -> [VideoItem] {
        let ids = playlist.itemIDs
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<VideoItem>(predicate: #Predicate { ids.contains($0.id) })
        let found = (try? context.fetch(descriptor)) ?? []
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    @discardableResult
    static func create(name: String, items: [VideoItem], in context: ModelContext) -> Playlist {
        let playlist = Playlist(name: cleanName(name).isEmpty ? "Плейлист" : cleanName(name),
                                itemIDs: items.map(\.id))
        context.insert(playlist)
        try? context.save()
        return playlist
    }

    static func add(_ items: [VideoItem], to playlist: Playlist, in context: ModelContext) {
        playlist.append(items.map(\.id))
        try? context.save()
    }

    static func rename(_ playlist: Playlist, to name: String, in context: ModelContext) {
        let cleaned = cleanName(name)
        guard !cleaned.isEmpty else { return }
        playlist.name = cleaned
        try? context.save()
    }

    static func delete(_ playlist: Playlist, in context: ModelContext) {
        context.delete(playlist)
        try? context.save()
    }

    /// Видео заменили тем же роликом в другом качестве — новое встаёт на его место.
    static func substitute(_ oldID: UUID, with newID: UUID, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        for playlist in all where playlist.contains(oldID) {
            playlist.itemIDs = Playlist.unique(playlist.itemIDs.map { $0 == oldID ? newID : $0 })
        }
    }

    /// Видео удалили из библиотеки — убираем его из всех плейлистов.
    static func forget(_ videoID: UUID, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        for playlist in all where playlist.contains(videoID) { playlist.remove(videoID) }
    }

    /// Общая длительность — «1:23:45» в подписи плейлиста.
    static func totalDuration(of items: [VideoItem]) -> Double {
        items.reduce(0) { $0 + max(0, $1.duration ?? 0) }
    }

    /// «Плейлист 3» — следующий номер после уже выданных. Свои названия («Музыка») не считаются.
    static func suggestedName(existing: [String]) -> String {
        let prefix = "Плейлист "
        let numbers = existing.compactMap { $0.hasPrefix(prefix) ? Int($0.dropFirst(prefix.count)) : nil }
        return prefix + String((numbers.max() ?? 0) + 1)
    }

    static func cleanName(_ name: String) -> String {
        String(name.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(80))
    }
}
