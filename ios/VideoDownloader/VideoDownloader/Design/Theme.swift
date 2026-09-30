import SwiftUI
import UIKit
import YTVDAPI

/// Оформление в духе десктопного YTVD: те же цвета, «зерно» и плашки.
///
/// Цвета — ровно те же, что в Theme.swift Mac-приложения. Размеры увеличены под палец,
/// шрифты — через Dynamic Type, но с теми же начертаниями, что на Mac.
enum Theme {

    // MARK: - цвета

    static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: uiDynamic(dark: dark, light: light))
    }

    static func uiDynamic(dark: UInt32, light: UInt32) -> UIColor {
        UIColor { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) }
    }

    /// Те же цвета для UIKit — навигационной панели и системных списков.
    enum UIColors {
        static let chrome = Theme.uiDynamic(dark: 0x1C1C1C, light: 0xDCDCDE)
        static let bg = Theme.uiDynamic(dark: 0x242424, light: 0xECECED)
        static let text = Theme.uiDynamic(dark: 0xEAEAEA, light: 0x1B1B1C)
        static let sep = Theme.uiDynamic(dark: 0x151515, light: 0xC2C2C4)
        static let blue = UIColor(hex: 0x3B8FD1)
    }

    /// Навигационная панель вложенных экранов — в цвет шапки YTVD.
    static func applyAppearance() {
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColors.chrome
        bar.shadowColor = UIColors.sep
        bar.titleTextAttributes = [.foregroundColor: UIColors.text,
                                   .font: UIFont.preferredFont(forTextStyle: .headline)]
        bar.largeTitleTextAttributes = [.foregroundColor: UIColors.text]
        let appearance = UINavigationBar.appearance()
        appearance.standardAppearance = bar
        appearance.scrollEdgeAppearance = bar
        appearance.compactAppearance = bar
        appearance.tintColor = UIColors.blue
    }

    static let bg     = dynamic(dark: 0x242424, light: 0xECECED)
    static let bg2    = dynamic(dark: 0x2C2C2C, light: 0xE2E2E3)
    static let bg3    = dynamic(dark: 0x333333, light: 0xD8D8D9)
    static let lane   = dynamic(dark: 0x1F1F1F, light: 0xDCDCDD)
    static let sep    = dynamic(dark: 0x151515, light: 0xC2C2C4)
    static let chrome = dynamic(dark: 0x1C1C1C, light: 0xDCDCDE)
    static let text   = dynamic(dark: 0xEAEAEA, light: 0x1B1B1C)
    static let dim    = dynamic(dark: 0x9A9A9A, light: 0x5F5F62)
    static let muted  = dynamic(dark: 0x6E6E6E, light: 0x8B8B8F)
    static let hair   = dynamic(dark: 0x3A3A3A, light: 0xD0D0D2)
    static let focus  = dynamic(dark: 0xE6E6E6, light: 0x2A2A2C)
    /// Подложка предупреждения — как полоса «Не найден Deno» на Mac.
    static let warning = dynamic(dark: 0x45382B, light: 0xF1E2D2)

    static let blue   = Color(hex: 0x3B8FD1)
    static let orange = Color(hex: 0xE08B34)
    static let red    = Color(hex: 0xD74B3C)
    static let steel  = Color(hex: 0x6D7A86)
    static let green  = Color(hex: 0x4F9D5D)

    /// Площадка по строке из сервера или библиотеки: «youtube», «vk»…
    static func source(_ platform: String) -> MediaSource {
        MediaSource(rawValue: platform.lowercased()) ?? .other
    }

    static func sourceColor(_ source: MediaSource) -> Color {
        let c = source.accent
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    // MARK: - размеры

    enum Metrics {
        /// Плашки и кнопки. На Mac 5 — здесь чуть мягче под крупный экран.
        static let radius: CGFloat = 6
        /// Панели — как углы окна YTVD.
        static let panelRadius: CGFloat = 13
        static let blockHeight: CGFloat = 26
        static let buttonHeight: CGFloat = 50
        static let swatch: CGFloat = 12
        static let gutter: CGFloat = 12
    }

    // MARK: - шрифты: начертания как на Mac, размер — по настройке шрифта в iOS

    enum Font {
        static let row = SwiftUI.Font.system(.body, weight: .semibold)
        static let rowSub = SwiftUI.Font.system(.subheadline)
        static let title = SwiftUI.Font.system(.headline)
        static let meta = SwiftUI.Font.system(.footnote)
        static let group = SwiftUI.Font.system(.caption, weight: .semibold)
        static let badge = SwiftUI.Font.system(.caption2, weight: .bold)
        static let block = SwiftUI.Font.system(.footnote, weight: .bold).monospacedDigit()
        static let button = SwiftUI.Font.system(.body, weight: .semibold)
        static let logo = SwiftUI.Font.system(.subheadline, weight: .heavy)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

/// Зерно поверх плашек — та же фактура и то же начальное число, что на Mac.
enum Grain {

    static let tile: UIImage = {
        let side = 96
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in stride(from: 0, to: pixels.count, by: 4) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = UInt8((seed >> 33) & 0xFF)
            pixels[i] = value; pixels[i + 1] = value; pixels[i + 2] = value; pixels[i + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return UIImage() }
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }()

    static func overlay(opacity: Double) -> some View {
        Image(uiImage: tile)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}
