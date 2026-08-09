import AppKit
import Foundation

/// Следит за буфером обмена и сообщает о появлении поддерживаемой ссылки.
@MainActor
public final class ClipboardWatcher: ObservableObject {

    /// Ссылка, лежащая в буфере прямо сейчас (если она поддерживается и ещё не использована).
    @Published public private(set) var pendingURL: URL?

    private var timer: Timer?
    private var lastChangeCount: Int
    private var consumed: Set<String> = []
    private let pasteboard: NSPasteboard

    public var onDetect: ((URL) -> Void)?

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start(interval: TimeInterval = 0.7) {
        stop()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        timer.tolerance = interval / 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        check()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Помечает ссылку как отработанную, чтобы подсказка не появлялась второй раз.
    public func consume(_ url: URL) {
        consumed.insert(url.absoluteString)
        if pendingURL == url { pendingURL = nil }
    }

    public func clear() { pendingURL = nil }

    private func check() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let text = pasteboard.string(forType: .string),
              let url = LinkDetector.firstSupportedURL(in: text),
              !consumed.contains(url.absoluteString)
        else { return }

        pendingURL = url
        onDetect?(url)
    }
}
