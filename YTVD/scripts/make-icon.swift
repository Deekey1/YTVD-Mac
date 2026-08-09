#!/usr/bin/env swift
// Рисует иконку приложения: три плашки-дорожки на тёмном фоне — тот же язык, что и в окне.
// Запуск: swift scripts/make-icon.swift <каталог-назначения>

import AppKit
import Foundation

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let bars: [(width: CGFloat, color: NSColor)] = [
    (0.72, color(0x3B8FD1)),   // синий — видео
    (0.50, color(0xE08B34)),   // оранжевый — экономный кодек
    (0.30, color(0xD74B3C)),   // красный — звук
]

func drawIcon(side: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    defer { image.unlockFocus() }

    let inset = side * 0.08
    let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = rect.width * 0.225

    // Подложка
    let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    color(0x242424).setFill()
    background.fill()
    background.addClip()

    NSGradient(colors: [color(0x3A3A3A).withAlphaComponent(0.9), color(0x1C1C1C)])?
        .draw(in: rect, angle: -90)

    // Плашки
    let barHeight = rect.height * 0.15
    let gap = rect.height * 0.085
    let totalHeight = barHeight * 3 + gap * 2
    let left = rect.minX + rect.width * 0.13
    var y = rect.midY + totalHeight / 2 - barHeight

    for bar in bars {
        let barRect = NSRect(x: left, y: y, width: rect.width * bar.width, height: barHeight)
        let corner = barHeight * 0.26
        let path = NSBezierPath(roundedRect: barRect, xRadius: corner, yRadius: corner)
        bar.color.setFill()
        path.fill()

        // Объём: светлая кромка сверху, тень снизу.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.26),
                            NSColor.clear,
                            NSColor.black.withAlphaComponent(0.22)])?.draw(in: barRect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = max(1, side / 256)
        path.stroke()

        y -= barHeight + gap
    }

    return image
}

let sizes: [(px: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
    (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

let iconset = output.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in sizes {
    let image = drawIcon(side: CGFloat(size.px))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("не удалось отрисовать \(size.name)\n".utf8))
        exit(1)
    }
    try png.write(to: iconset.appendingPathComponent("\(size.name).png"))
}

print("iconset готов: \(iconset.path)")
