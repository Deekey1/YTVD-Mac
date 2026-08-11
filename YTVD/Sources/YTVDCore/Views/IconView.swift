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
enum IconCache {
    struct Entry {
        let cgPath: CGPath
        let dash: [CGFloat]
        let filled: Bool
    }

    private static var storage: [String: [Entry]] = [:]
    private static let lock = NSLock()

    static func paths(for icon: Icon) -> [Entry] {
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

/// Кнопка-иконка в шапке окна и панелях.
public struct IconButton: View {
    let icon: Icon
    let active: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    public init(_ icon: Icon, active: Bool = false, help: String = "", action: @escaping () -> Void) {
        self.icon = icon; self.active = active; self.help = help; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            IconView(icon, size: 15)
                .foregroundStyle(active ? Color.white : (hovering ? Theme.text : Theme.muted))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(active ? Theme.blue : (hovering ? Theme.bg3 : .clear))
                )
                // Прозрачная подложка нажатий не принимает — задаём область явно.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
