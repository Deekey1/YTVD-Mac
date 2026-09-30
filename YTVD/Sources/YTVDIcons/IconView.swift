import SwiftUI

/// Иконка из набора Obra Icons: контуры разбираются один раз и кэшируются.
public struct IconView: View {
    public let icon: Icon
    public let size: CGFloat
    public let lineWidth: CGFloat

    public init(_ icon: Icon, size: CGFloat = 15, lineWidth: CGFloat = 1.9) {
        self.icon = icon
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            for entry in IconCache.paths(for: icon) {
                var path = Path(entry.cgPath)
                path = path.applying(CGAffineTransform(scaleX: scale, y: scale))
                if entry.filled {
                    context.fill(path, with: .style(.foreground))
                } else {
                    context.stroke(path, with: .style(.foreground),
                                   style: StrokeStyle(lineWidth: lineWidth * scale,
                                                      lineCap: .round, lineJoin: .round,
                                                      dash: entry.dash.map { $0 * scale }))
                }
            }
        }
        .frame(width: size, height: size)
        // Штрихи не должны обрезаться по краю холста.
        .allowsHitTesting(false)
    }
}

/// Разобранные контуры живут в памяти всё время работы — их всего пара десятков.
/// Открыт наружу: по нему же рисуются картинки иконок на Mac и на iPhone.
public enum IconCache {
    public struct Entry {
        public let cgPath: CGPath
        public let dash: [CGFloat]
        public let filled: Bool
    }

    nonisolated(unsafe) private static var storage: [String: [Entry]] = [:]
    private static let lock = NSLock()

    public static func paths(for icon: Icon) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[icon.rawValue] { return cached }
        let entries = icon.paths.map {
            Entry(cgPath: SVGPath.parse($0.d), dash: $0.dash, filled: $0.filled)
        }
        storage[icon.rawValue] = entries
        return entries
    }
}
