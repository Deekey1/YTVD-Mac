import Foundation
import Observation
import SwiftData
import UIKit
import YTVDAPI

/// Состояние вкладки «Скачать»: ссылка → разбор на Mac → выбор качества → загрузка.
@Observable @MainActor
final class DownloadModel {

    enum State: Equatable {
        case idle
        case resolving
        case ready(VideoInfo)
        case failed(String)
    }

    /// «Видео уже в библиотеке» — что делать дальше, решает пользователь.
    struct Duplicate: Identifiable {
        let id = UUID()
        let existing: VideoItem
        let video: VideoInfo
        let format: VideoFormat
    }

    var text = ""
    private(set) var state: State = .idle
    var selectedFormatId: String?
    private(set) var isStarting = false
    var duplicate: Duplicate?
    var alert: String?
    /// В буфере обмена, похоже, ссылка. Проверяем без чтения — iOS не спросит разрешения.
    private(set) var clipboardHasLink = false
    @ObservationIgnored private var resolveTask: Task<Void, Never>?

    var video: VideoInfo? {
        if case .ready(let video) = state { return video }
        return nil
    }

    var selectedFormat: VideoFormat? {
        video?.formats.first { $0.id == selectedFormatId }
    }

    var canResolve: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state != .resolving
    }

    // MARK: - разбор ссылки

    func resolve(connection: Connection) {
        guard let url = LinkDetector.firstSupportedURL(in: text) else {
            state = .failed(AppError.invalidURL.localizedDescription)
            return
        }
        text = url.absoluteString
        state = .resolving
        selectedFormatId = nil
        resolveTask?.cancel()
        resolveTask = Task {
            do {
                let video = try await connection.client().resolve(url.absoluteString)
                guard !Task.isCancelled else { return }
                state = .ready(video)
                selectedFormatId = Prefs.quality.pick(from: video.formats)?.id ?? video.recommendedFormatId
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(AppError.from(error).localizedDescription)
            }
        }
    }

    func clear() {
        resolveTask?.cancel()
        text = ""
        state = .idle
        selectedFormatId = nil
    }

    // MARK: - скачать

    /// Первое нажатие «Скачать»: сначала проверяем, нет ли ролика в библиотеке.
    func download(context: ModelContext, transfers: TransferService) {
        guard let video, let format = selectedFormat else { return }
        if transfers.isDownloading(videoId: video.id, formatId: format.id) {
            alert = "Этот ролик в таком качестве уже скачивается"
            return
        }
        if let existing = Library.duplicates(of: video.id, in: context).first {
            duplicate = Duplicate(existing: existing, video: video, format: format)
            return
        }
        start(video: video, format: format, replacing: nil, transfers: transfers)
    }

    func start(video: VideoInfo, format: VideoFormat, replacing: UUID?, transfers: TransferService) {
        isStarting = true
        Task {
            defer { isStarting = false }
            do {
                try await transfers.start(video: video, format: format, replacing: replacing)
                clear()
            } catch {
                alert = AppError.from(error).localizedDescription
            }
        }
    }

    // MARK: - буфер обмена

    func refreshClipboardHint() {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasURLs || pasteboard.hasStrings else {
            clipboardHasLink = false
            return
        }
        if pasteboard.hasURLs {
            clipboardHasLink = true
            return
        }
        // detectedPatterns не читает содержимое, поэтому не вызывает запрос «Разрешить вставку».
        Task {
            let found = (try? await pasteboard.detectedPatterns(for: [\.probableWebURL]))?
                .contains(\UIPasteboard.DetectedValues.probableWebURL) ?? false
            clipboardHasLink = found
        }
    }

    /// То, что пришло из кнопки «Вставить»: ссылка или текст со ссылкой внутри.
    func paste(_ providers: [NSItemProvider], connection: Connection) {
        Task {
            guard let text = await Self.text(from: providers) else { return }
            self.text = text
            clipboardHasLink = false
            resolve(connection: connection)
        }
    }

    private static func text(from providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self), let url = await load(URL.self, from: provider) {
                return url.absoluteString
            }
            if provider.canLoadObject(ofClass: String.self), let text = await load(String.self, from: provider) {
                return text
            }
        }
        return nil
    }

    private static func load<T: _ObjectiveCBridgeable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
    where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
        }
    }
}
