// swift-tools-version: 6.0
import PackageDescription

let settings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "YTVD",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Контракт API — его же подключает iPhone-приложение, чтобы модели не разъезжались.
        .library(name: "YTVDAPI", targets: ["YTVDAPI"]),
    ],
    targets: [
        // Модели запросов и ответов, разбор ссылок. Только Foundation — собирается и под iOS.
        .target(name: "YTVDAPI", path: "Sources/YTVDAPI", swiftSettings: settings),
        // Вся логика и интерфейс Mac-приложения, плюс сервер для iPhone.
        .target(name: "YTVDCore", dependencies: ["YTVDAPI"], path: "Sources/YTVDCore",
                swiftSettings: settings),
        // Исполняемый файл — только точка входа.
        .executableTarget(name: "YTVD", dependencies: ["YTVDCore"], path: "Sources/YTVD",
                          swiftSettings: settings),
        .testTarget(name: "YTVDCoreTests", dependencies: ["YTVDCore"], path: "Tests/YTVDCoreTests",
                    swiftSettings: settings),
        .testTarget(name: "YTVDServerTests", dependencies: ["YTVDCore", "YTVDAPI"],
                    path: "Tests/YTVDServerTests", resources: [.copy("Fixtures")],
                    swiftSettings: settings),
    ]
)
