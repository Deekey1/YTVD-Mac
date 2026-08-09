import AppKit

/// Отрисовка иконки Obra в NSImage — нужна для значка в меню-баре.
public extension Icon {

    func templateImage(size: CGFloat = 18, lineWidth: CGFloat = 1.9) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = min(rect.width, rect.height) / 24

            // SVG растёт вниз, AppKit — вверх: переворачиваем систему координат.
            context.translateBy(x: 0, y: rect.height)
            context.scaleBy(x: scale, y: -scale)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setLineWidth(lineWidth)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)

            for entry in IconCache.paths(for: self) {
                context.addPath(entry.cgPath)
                if entry.filled {
                    context.fillPath()
                } else {
                    if !entry.dash.isEmpty { context.setLineDash(phase: 0, lengths: entry.dash) }
                    context.strokePath()
                    context.setLineDash(phase: 0, lengths: [])
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
