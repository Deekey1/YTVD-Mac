// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YTVD",
    platforms: [.macOS(.v14)],
    targets: [
        // Вся логика и интерфейс — в библиотеке, чтобы их можно было покрыть тестами.
        .target(name: "YTVDCore", path: "Sources/YTVDCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        // Исполняемый файл — только точка входа.
        .executableTarget(name: "YTVD", dependencies: ["YTVDCore"], path: "Sources/YTVD",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "YTVDCoreTests", dependencies: ["YTVDCore"], path: "Tests/YTVDCoreTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
