import AppKit
import Foundation

/// Загрузка и сохранение обложки.
public enum ThumbnailService {

    public static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw YTVDError.network("Обложка не загрузилась (код \(http.statusCode))")
            }
            guard !data.isEmpty else { throw YTVDError.network("Обложка пустая") }
            return data
        } catch let error as YTVDError {
            throw error
        } catch {
            throw YTVDError.network("Обложка не загрузилась: \(error.localizedDescription)")
        }
    }

    /// Первая обложка из списка, которая реально скачалась. Лучшей по данным площадки
    /// может не быть: у старых роликов YouTube отвечает 404 на maxresdefault.
    public static func fetchFirst(_ candidates: [String]) async throws -> Data {
        var lastError: Error = YTVDError.network("У ролика нет обложки")
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            do { return try await fetch(url) } catch { lastError = error }
        }
        throw lastError
    }

    public static func image(from data: Data) -> NSImage? { NSImage(data: data) }

    /// Приводит что угодно (webp, png, jpeg) к JPEG.
    public static func jpegData(from data: Data, quality: CGFloat = 0.95) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Скачивает обложку и кладёт рядом JPEG. Возвращает путь к файлу.
    @discardableResult
    public static func saveJPEG(from url: URL, to destination: URL) async throws -> URL {
        try write(try await fetch(url), to: destination)
    }

    /// То же, но с запасными адресами: берётся первый, что открылся.
    @discardableResult
    public static func saveJPEG(fromFirstOf candidates: [String], to destination: URL) async throws -> URL {
        try write(try await fetchFirst(candidates), to: destination)
    }

    private static func write(_ data: Data, to destination: URL) throws -> URL {
        guard let jpeg = jpegData(from: data) else {
            throw YTVDError.network("Не удалось перевести обложку в JPEG")
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try jpeg.write(to: destination, options: .atomic)
        return destination
    }
}
