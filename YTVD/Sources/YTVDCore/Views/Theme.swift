import AppKit
import SwiftUI

/// Цвета, размеры и «зерно» — единый источник оформления.
public enum Theme {

    // MARK: - размеры

    public enum Metrics {
        public static let windowWidth: CGFloat = 400
        public static let titleBar: CGFloat = 34
        public static let urlBar: CGFloat = 42
        public static let rowHeight: CGFloat = 28
        public static let groupHeight: CGFloat = 22
        public static let headerColumn: CGFloat = 150
        public static let laneLeading: CGFloat = 5
        public static let laneTrailing: CGFloat = 10
        public static let blockHeight: CGFloat = 20
        public static let radius: CGFloat = 5
        public static let windowRadius: CGFloat = 13
        public static let compactThumb: CGFloat = 150

        /// Ширина дорожки, в которой рисуются плашки.
        public static var lane: CGFloat { windowWidth - headerColumn - laneLeading - laneTrailing }
    }

    // MARK: - цвета

    static func dynamic(dark: String, light: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    public static let bg      = dynamic(dark: "242424", light: "ECECED")
    public static let bg2     = dynamic(dark: "2C2C2C", light: "E2E2E3")
    public static let bg3     = dynamic(dark: "333333", light: "D8D8D9")
    public static let lane    = dynamic(dark: "1F1F1F", light: "DCDCDD")
    public static let sep     = dynamic(dark: "151515", light: "C2C2C4")
    public static let chrome  = dynamic(dark: "1C1C1C", light: "DCDCDE")
    public static let text    = dynamic(dark: "EAEAEA", light: "1B1B1C")
    public static let dim     = dynamic(dark: "9A9A9A", light: "5F5F62")
    public static let muted   = dynamic(dark: "6E6E6E", light: "8B8B8F")
    public static let hair    = dynamic(dark: "3A3A3A", light: "D0D0D2")
    public static let focus   = dynamic(dark: "E6E6E6", light: "2A2A2C")

    public static let blue   = Color(nsColor: NSColor(hex: "3B8FD1"))
    public static let orange = Color(nsColor: NSColor(hex: "E08B34"))
    public static let red    = Color(nsColor: NSColor(hex: "D74B3C"))
    public static let steel  = Color(nsColor: NSColor(hex: "6D7A86"))
    public static let green  = Color(nsColor: NSColor(hex: "4F9D5D"))

    public static func tint(_ tint: DownloadOption.Tint) -> Color {
        switch tint {
        case .blue: blue
        case .orange: orange
        case .red: red
        case .steel: steel
        }
    }

    public static func sourceColor(_ source: MediaSource) -> Color {
        let c = source.accent
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    // MARK: - шрифты

    public enum Font {
        public static let row = SwiftUI.Font.system(size: 12, weight: .medium)
        public static let rowSub = SwiftUI.Font.system(size: 11)
        public static let block = SwiftUI.Font.system(size: 10.5, weight: .semibold)
        public static let group = SwiftUI.Font.system(size: 9.5, weight: .semibold)
        public static let meta = SwiftUI.Font.system(size: 11)
        public static let title = SwiftUI.Font.system(size: 12.5, weight: .semibold)
        public static let badge = SwiftUI.Font.system(size: 9, weight: .bold)
        public static let hint = SwiftUI.Font.system(size: 10)
        public static let detail = SwiftUI.Font.system(size: 11)
        public static let button = SwiftUI.Font.system(size: 13, weight: .semibold)
    }
}

/// Признак офскрин-снимка: ImageRenderer не умеет рисовать TextField и ScrollView,
/// поэтому в режиме снимка их заменяют статичные аналоги. На работу приложения не влияет.
private struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var ytvdSnapshot: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Зерно поверх плашек — та же фактура, что в утверждённом прототипе.
public enum Grain {

    public static let tile: NSImage = {
        let side = 96
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        var seed: UInt64 = 0x9E3779B97F4A7C15            // фиксированное зерно — картинка стабильна
        for i in stride(from: 0, to: pixels.count, by: 4) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = UInt8((seed >> 33) & 0xFF)
            pixels[i] = value; pixels[i + 1] = value; pixels[i + 2] = value; pixels[i + 3] = 255
        }

        let image = NSImage(size: NSSize(width: side, height: side))
        if let provider = CGDataProvider(data: Data(pixels) as CFData),
           let cgImage = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: bytesPerRow,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false,
                                 intent: .defaultIntent) {
            image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        }
        return image
    }()

    public static func overlay(opacity: Double) -> some View {
        Image(nsImage: tile)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

/// Плашка: заливка цветом, объёмный градиент, тонкая тёмная обводка и зерно.
public struct BlockBackground: View {
    public let color: Color
    public let radius: CGFloat

    public init(color: Color, radius: CGFloat = Theme.Metrics.radius) {
        self.color = color
        self.radius = radius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .overlay(
                LinearGradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.16)],
                               startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay(Grain.overlay(opacity: 0.16).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.black.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 1, y: 1)
    }
}

/// Горизонтальная линия-разделитель толщиной в один пиксель.
public struct Hairline: View {
    public init() {}
    public var body: some View {
        Theme.sep.frame(height: 1)
    }
}
