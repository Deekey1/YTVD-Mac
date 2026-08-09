import Foundation

public struct HistoryEntry: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var quality: String          // «1080p · MP4»
    public var bytes: Int64
    public var path: String
    public var sourceRaw: String
    public var date: Date

    public var source: MediaSource { MediaSource(rawValue: sourceRaw) ?? .other }
    public var url: URL { URL(fileURLWithPath: path) }
    public var fileExists: Bool { FileManager.default.fileExists(atPath: path) }

    public init(id: UUID = UUID(), title: String, quality: String, bytes: Int64,
                path: String, source: MediaSource, date: Date = Date()) {
        self.id = id; self.title = title; self.quality = quality; self.bytes = bytes
        self.path = path; self.sourceRaw = source.rawValue; self.date = date
    }
}

/// История скачиваний — простой JSON рядом с настройками.
@MainActor
public final class HistoryStore: ObservableObject {

    @Published public private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private let limit: Int

    public init(fileURL: URL? = nil, limit: Int = 60) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.fileURL = fileURL ?? base.appendingPathComponent("YTVD/history.json")
        self.limit = limit
        load()
    }

    public var totalBytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }

    public func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    public func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("YTVD: не удалось сохранить историю — \(error.localizedDescription)")
        }
    }
}
