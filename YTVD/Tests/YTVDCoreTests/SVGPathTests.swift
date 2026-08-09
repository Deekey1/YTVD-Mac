import XCTest
@testable import YTVDCore

final class SVGPathTests: XCTestCase {

    func testStraightLine() {
        let path = SVGPath.parse("M12 16V3")
        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.boundingBox.minX, 12, accuracy: 0.001)
        XCTAssertEqual(path.boundingBox.minY, 3, accuracy: 0.001)
        XCTAssertEqual(path.boundingBox.height, 13, accuracy: 0.001)
    }

    func testPolyline() {
        let path = SVGPath.parse("M16 12L12 16L8 12")
        XCTAssertEqual(path.boundingBox.minX, 8, accuracy: 0.001)
        XCTAssertEqual(path.boundingBox.maxX, 16, accuracy: 0.001)
        XCTAssertEqual(path.boundingBox.maxY, 16, accuracy: 0.001)
    }

    func testCubicCurveAndClose() {
        let d = "M19 4H5C4.44772 4 4 4.44772 4 5V19C4 19.5523 4.44772 20 5 20H19C19.5523 20 20 19.5523 20 19V5C20 4.44772 19.5523 4 19 4Z"
        let path = SVGPath.parse(d)
        XCTAssertFalse(path.isEmpty)
        let box = path.boundingBox
        XCTAssertEqual(box.minX, 4, accuracy: 0.01)
        XCTAssertEqual(box.minY, 4, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 20, accuracy: 0.01)
        XCTAssertEqual(box.maxY, 20, accuracy: 0.01)
    }

    func testRelativeCommands() {
        let absolute = SVGPath.parse("M10 10L20 10L20 20")
        let relative = SVGPath.parse("m10 10l10 0l0 10")
        XCTAssertEqual(absolute.boundingBox.minX, relative.boundingBox.minX, accuracy: 0.001)
        XCTAssertEqual(absolute.boundingBox.maxX, relative.boundingBox.maxX, accuracy: 0.001)
        XCTAssertEqual(absolute.boundingBox.maxY, relative.boundingBox.maxY, accuracy: 0.001)
    }

    func testImplicitLineToAfterMoveTo() {
        // «M0 0 10 0 10 10» — вторая и третья пары координат означают линии.
        let path = SVGPath.parse("M0 0 10 0 10 10")
        XCTAssertEqual(path.boundingBox.maxX, 10, accuracy: 0.001)
        XCTAssertEqual(path.boundingBox.maxY, 10, accuracy: 0.001)
    }

    func testNegativeAndDecimalNumbersWithoutSeparators() {
        let path = SVGPath.parse("M0 0L-5.5-2.25")
        XCTAssertEqual(path.boundingBox.minX, -5.5, accuracy: 0.001)
        XCTAssertEqual(path.boundingBox.minY, -2.25, accuracy: 0.001)
    }

    func testHorizontalAndVerticalRelative() {
        let path = SVGPath.parse("M5 5h10v10")
        XCTAssertEqual(path.boundingBox.maxX, 15, accuracy: 0.001)
        XCTAssertEqual(path.boundingBox.maxY, 15, accuracy: 0.001)
    }

    func testSmoothCubicUsesReflectedControlPoint() {
        let path = SVGPath.parse("M0 0C2 0 4 2 4 4S8 8 8 8")
        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.boundingBox.maxX, 8, accuracy: 0.5)
    }

    func testGarbageDoesNotCrash() {
        XCTAssertTrue(SVGPath.parse("").isEmpty)
        XCTAssertTrue(SVGPath.parse("   ").isEmpty)
        XCTAssertTrue(SVGPath.parse("nonsense").isEmpty)
        _ = SVGPath.parse("M10")            // незаконченная команда
        _ = SVGPath.parse("L10 10")         // линия без начала
        _ = SVGPath.parse("M0 0A5 5 0 0 1 10 10")  // дуга не поддержана — просто обрывается
    }

    func testEveryBundledIconParsesIntoNonEmptyPath() {
        for icon in Icon.allCases {
            XCTAssertFalse(icon.paths.isEmpty, "у иконки \(icon.rawValue) нет контуров")
            for entry in icon.paths {
                let path = SVGPath.parse(entry.d)
                XCTAssertFalse(path.isEmpty, "контур иконки \(icon.rawValue) пустой: \(entry.d)")
                let box = path.boundingBox
                XCTAssertTrue(box.minX >= -1 && box.maxX <= 25 && box.minY >= -1 && box.maxY <= 25,
                              "иконка \(icon.rawValue) выходит за сетку 24×24: \(box)")
            }
        }
    }
}
