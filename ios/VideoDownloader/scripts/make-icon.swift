#!/usr/bin/env swift
// Иконка iPhone-клиента: кадр киноплёнки со стрелкой вниз — «скачать видео» с первого взгляда.
// iOS сам скругляет углы, поэтому фон — на весь квадрат и без прозрачности.
// Запуск: swift scripts/make-icon.swift VideoDownloader/Assets.xcassets/AppIcon.appiconset/AppIcon.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
let side = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 32 бита на точку: Quartz не рисует в 24-битный растр — картинка молча осталась бы чёрной.
let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
c.translateBy(x: 0, y: CGFloat(side))
c.scaleBy(x: 1, y: -1)                       // дальше y растёт вниз, как на макете

// Фон — синий, как акцентный цвет приложения.
let gradient = CGGradient(colorsSpace: space, colors: [color(0x4AA6EE), color(0x1B57AE)] as CFArray,
                          locations: [0, 1])!
c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: side), options: [])

// Кадр плёнки с мягкой тенью.
let card = CGRect(x: 232, y: 150, width: 560, height: 724)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: color(0x0A2A55, 0.28))
c.addPath(rounded(card, 70))
c.setFillColor(color(0xFFFFFF))
c.fillPath()
c.restoreGState()

// Перфорация по краям.
for column in [card.minX + 34, card.maxX - 34 - 58] {
    for row in 0..<6 {
        c.addPath(rounded(CGRect(x: column, y: card.minY + 62 + CGFloat(row) * 108, width: 58, height: 52), 14))
    }
}
c.setFillColor(color(0x2F7FD4))
c.fillPath()

// Стрелка вниз. Обводка тем же цветом скругляет острые углы.
let arrow = CGMutablePath()
let (x, top, bottom, shaft, head, neck) = (CGFloat(512), CGFloat(290), CGFloat(726), CGFloat(128), CGFloat(290), CGFloat(540))
arrow.move(to: CGPoint(x: x - shaft / 2, y: top))
arrow.addLine(to: CGPoint(x: x + shaft / 2, y: top))
arrow.addLine(to: CGPoint(x: x + shaft / 2, y: neck))
arrow.addLine(to: CGPoint(x: x + head / 2, y: neck))
arrow.addLine(to: CGPoint(x: x, y: bottom))
arrow.addLine(to: CGPoint(x: x - head / 2, y: neck))
arrow.addLine(to: CGPoint(x: x - shaft / 2, y: neck))
arrow.closeSubpath()
c.addPath(arrow)
c.setFillColor(color(0x1F66C2))
c.fillPath()
c.addPath(arrow)
c.setStrokeColor(color(0x1F66C2))
c.setLineWidth(36)
c.setLineJoin(.round)
c.strokePath()

let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, c.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("не записалась иконка") }
print("иконка: \(output.path)")
