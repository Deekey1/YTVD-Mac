import CoreGraphics
import Foundation

/// Разбор атрибута `d` из SVG в `CGPath`.
///
/// Поддержаны команды M, L, H, V, C, S, Q, T, Z в абсолютном и относительном виде —
/// этого достаточно для всего используемого набора Obra Icons (дуг в нём нет).
public enum SVGPath {

    public static func parse(_ d: String) -> CGPath {
        let path = CGMutablePath()
        let chars = Array(d)
        var i = 0

        var cur = CGPoint.zero          // текущая точка
        var subStart = CGPoint.zero     // начало подконтура
        var lastCubic: CGPoint?         // последняя контрольная точка кубической кривой
        var lastQuad: CGPoint?          // ... квадратичной
        var command: Character = " "
        var started = false

        func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n"
                    || chars[i] == "\t" || chars[i] == "\r" { i += 1 }
        }

        func nextNumber() -> CGFloat? {
            skipSeparators()
            var j = i
            if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
            var sawDigit = false
            while j < chars.count, chars[j].isNumber { j += 1; sawDigit = true }
            if j < chars.count, chars[j] == "." {
                j += 1
                while j < chars.count, chars[j].isNumber { j += 1; sawDigit = true }
            }
            guard sawDigit else { return nil }
            if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                var k = j + 1
                if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
                var expDigits = false
                while k < chars.count, chars[k].isNumber { k += 1; expDigits = true }
                if expDigits { j = k }
            }
            let text = String(chars[i..<j])
            i = j
            return Double(text).map { CGFloat($0) }
        }

        func nextPoint(relative: Bool) -> CGPoint? {
            guard let x = nextNumber(), let y = nextNumber() else { return nil }
            return relative ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
        }

        /// Отражение прошлой контрольной точки — для S и T.
        func reflected(_ control: CGPoint?) -> CGPoint {
            guard let control else { return cur }
            return CGPoint(x: 2 * cur.x - control.x, y: 2 * cur.y - control.y)
        }

        while i < chars.count {
            skipSeparators()
            guard i < chars.count else { break }

            if chars[i].isLetter {
                command = chars[i]
                i += 1
            } else if command == " " {
                break                                   // мусор до первой команды
            } else if command == "M" || command == "m" {
                command = command == "M" ? "L" : "l"    // повтор после M — это линии
            }

            let relative = command.isLowercase
            switch Character(command.lowercased()) {
            case "m":
                guard let p = nextPoint(relative: relative) else { i = chars.count; break }
                path.move(to: p)
                cur = p; subStart = p; started = true
                lastCubic = nil; lastQuad = nil

            case "l":
                guard started, let p = nextPoint(relative: relative) else { i = chars.count; break }
                path.addLine(to: p)
                cur = p; lastCubic = nil; lastQuad = nil

            case "h":
                guard started, let x = nextNumber() else { i = chars.count; break }
                let p = CGPoint(x: relative ? cur.x + x : x, y: cur.y)
                path.addLine(to: p)
                cur = p; lastCubic = nil; lastQuad = nil

            case "v":
                guard started, let y = nextNumber() else { i = chars.count; break }
                let p = CGPoint(x: cur.x, y: relative ? cur.y + y : y)
                path.addLine(to: p)
                cur = p; lastCubic = nil; lastQuad = nil

            case "c":
                guard started,
                      let c1 = nextPoint(relative: relative),
                      let c2 = nextPoint(relative: relative),
                      let p = nextPoint(relative: relative) else { i = chars.count; break }
                path.addCurve(to: p, control1: c1, control2: c2)
                cur = p; lastCubic = c2; lastQuad = nil

            case "s":
                guard started,
                      let c2 = nextPoint(relative: relative),
                      let p = nextPoint(relative: relative) else { i = chars.count; break }
                path.addCurve(to: p, control1: reflected(lastCubic), control2: c2)
                cur = p; lastCubic = c2; lastQuad = nil

            case "q":
                guard started,
                      let c = nextPoint(relative: relative),
                      let p = nextPoint(relative: relative) else { i = chars.count; break }
                path.addQuadCurve(to: p, control: c)
                cur = p; lastQuad = c; lastCubic = nil

            case "t":
                guard started, let p = nextPoint(relative: relative) else { i = chars.count; break }
                let c = reflected(lastQuad)
                path.addQuadCurve(to: p, control: c)
                cur = p; lastQuad = c; lastCubic = nil

            case "z":
                guard started else { break }
                path.closeSubpath()
                cur = subStart
                lastCubic = nil; lastQuad = nil

            default:
                i = chars.count                          // неизвестная команда — прекращаем
            }
        }

        return path
    }
}
