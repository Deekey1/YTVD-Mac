import Foundation
import Observation

/// Где остановился просмотр каждого видео.
///
/// Хранится в отдельном маленьком файле, а не в базе библиотеки: запись идёт через
/// F_FULLFSYNC, поэтому место не теряется и при жёсткой перезагрузке — обычная запись
/// может задержаться в кэше накопителя и пропасть вместе с питанием.
@MainActor @Observable
final class PlaybackPositions {

    struct Entry: Codable, Equatable {
        var seconds: Double
        var duration: Double?
        var updatedAt: Date
    }

    static let shared = PlaybackPositions(url: LibraryFiles.root.appendingPathComponent("Positions.json"))

    /// Меньше — смотреть сначала: пять секунд не стоят того, чтобы помнить.
    static let minimumResume: Double = 5
    /// Ближе к концу — досмотрено: следующий просмотр начнётся сначала.
    static let finishedMargin: Double = 10
    static let finishedFraction: Double = 0.97

    private(set) var entries: [UUID: Entry] = [:]
    @ObservationIgnored private let writer: DurableWriter

    init(url: URL) {
        writer = DurableWriter(url: url)
        entries = Self.load(from: url)
    }

    /// С какого места продолжать; nil — сначала.
    func resumeTime(for id: UUID) -> Double? {
        guard let entry = entries[id], Self.isResumable(entry.seconds, duration: entry.duration) else { return nil }
        return entry.seconds
    }

    /// Доля просмотренного — для полосы на обложке.
    func progress(for id: UUID) -> Double? {
        guard let entry = entries[id], let duration = entry.duration, duration > 0,
              Self.isResumable(entry.seconds, duration: duration) else { return nil }
        return min(1, entry.seconds / duration)
    }

    /// Какое из видео начали смотреть последним и не досмотрели — с него продолжается плейлист.
    func lastStarted(among ids: [UUID]) -> UUID? {
        ids.compactMap { id in entries[id].map { (id: id, entry: $0) } }
            .filter { Self.isResumable($0.entry.seconds, duration: $0.entry.duration) }
            .max { $0.entry.updatedAt < $1.entry.updatedAt }?
            .id
    }

    /// Запомнить место. Досмотренное и едва начатое забываем: в следующий раз — сначала.
    func record(_ seconds: Double, duration: Double?, for id: UUID, now: Date = Date()) {
        guard seconds.isFinite, seconds >= 0 else { return }
        let known = (duration?.isFinite == true && (duration ?? 0) > 0) ? duration : entries[id]?.duration
        if Self.isResumable(seconds, duration: known) {
            // Место почти не сдвинулось — файл не трогаем.
            if let old = entries[id], abs(old.seconds - seconds) < 0.5, old.duration == known { return }
            entries[id] = Entry(seconds: seconds, duration: known, updatedAt: now)
        } else {
            guard entries.removeValue(forKey: id) != nil else { return }
        }
        writer.write(Self.encode(entries))
    }

    func clear(_ id: UUID) {
        guard entries.removeValue(forKey: id) != nil else { return }
        writer.write(Self.encode(entries))
    }

    /// Ролик заменили тем же в другом качестве — место переезжает к новой записи.
    func move(from oldID: UUID, to newID: UUID) {
        guard let entry = entries.removeValue(forKey: oldID) else { return }
        entries[newID] = entry
        writer.write(Self.encode(entries))
    }

    /// Дождаться, пока записанное дойдёт до накопителя: перед уходом в фон и закрытием.
    func flush() { writer.flush() }

    // MARK: - правила

    nonisolated static func isResumable(_ seconds: Double, duration: Double?) -> Bool {
        seconds >= minimumResume && !isFinished(seconds, duration: duration)
    }

    nonisolated static func isFinished(_ seconds: Double, duration: Double?) -> Bool {
        guard let duration, duration > 0 else { return false }
        return seconds >= duration - finishedMargin || seconds / duration >= finishedFraction
    }

    // MARK: - файл

    private struct Stored: Codable {
        var version = 1
        var positions: [String: Entry]
    }

    nonisolated static func encode(_ entries: [UUID: Entry]) -> Data {
        let stored = Stored(positions: Dictionary(uniqueKeysWithValues: entries.map { ($0.key.uuidString, $0.value) }))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(stored)) ?? Data()
    }

    nonisolated static func load(from url: URL) -> [UUID: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(Stored.self, from: data) else { return [:] }
        var result: [UUID: Entry] = [:]
        for (key, entry) in stored.positions {
            if let id = UUID(uuidString: key) { result[id] = entry }
        }
        return result
    }
}

/// Запись файла, которая переживает внезапное отключение питания.
///
/// Пишем во временный файл, просим накопитель сбросить кэш (F_FULLFSYNC — обычный
/// fsync на устройствах Apple этого не гарантирует), переименовываем поверх старого
/// и синхронизируем каталог. В итоге на диске либо прежняя версия, либо новая целиком.
final class DurableWriter: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "studio.dk.videodownloader.positions", qos: .utility)

    init(url: URL) { self.url = url }

    /// В фоновой очереди — чтобы не дёргать интерфейс во время просмотра.
    func write(_ data: Data) {
        let url = self.url
        queue.async { _ = DurableWriter.writeDurably(data, to: url) }
    }

    /// Дождаться всех начатых записей.
    func flush() { queue.sync {} }

    @discardableResult
    static func writeDurably(_ data: Data, to url: URL) -> Bool {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).tmp")

        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return false }
        let written = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return true }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, base + offset, buffer.count - offset)
                if count <= 0 { return false }
                offset += count
            }
            return true
        }
        let synced = written && (fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0)
        close(fd)
        guard synced, rename(temporary.path, url.path) == 0 else {
            unlink(temporary.path)
            return false
        }
        // Переименование тоже должно дойти до накопителя.
        let directoryFD = open(directory.path, O_RDONLY)
        if directoryFD >= 0 {
            if fcntl(directoryFD, F_FULLFSYNC) != 0 { fsync(directoryFD) }
            close(directoryFD)
        }
        return true
    }
}
