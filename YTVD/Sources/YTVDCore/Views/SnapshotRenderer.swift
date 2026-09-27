import AppKit
import SwiftUI

/// Офскрин-снимки окна для проверки вёрстки: `YTVD --render <каталог>`.
/// Рисуется настоящий RootView с подставленными данными — без сети и без прав на запись экрана.
@MainActor
public enum SnapshotRenderer {

    public struct Shot {
        public let name: String
        public let dark: Bool
        public let build: (AppModel) -> Void
    }

    public static let shots: [Shot] = [
        Shot(name: "01-idle-dark", dark: true) { _ in },
        Shot(name: "02-clipboard-dark", dark: true) { model in
            model.setClipboardSuggestionForTesting(
                URL(string: "https://www.youtube.com/watch?v=aqz-KE-bpKQ"))
        },
        Shot(name: "02b-analyzing-dark", dark: true) { model in
            model.applyFixture(.analyzing)
        },
        Shot(name: "03-ready-dark", dark: true) { model in
            model.applyFixture(.ready)
        },
        Shot(name: "04-ready-expanded-dark", dark: true) { model in
            model.applyFixture(.ready)
            model.showAlternatives = true
            model.coverSelected = true
            if let alternative = model.options.first(where: \.isAlternative) {
                model.selectedID = alternative.id
                model.expandedID = alternative.id
            }
        },
        Shot(name: "05-downloading-dark", dark: true) { model in
            model.applyFixture(.downloading)
        },
        Shot(name: "06-done-dark", dark: true) { model in
            model.applyFixture(.done)
        },
        Shot(name: "07-error-dark", dark: true) { model in
            model.applyFixture(.failed)
        },
        Shot(name: "08-settings-dark", dark: true) { model in
            model.applyFixture(.ready)
            model.panel = .settings
        },
        Shot(name: "08b-settings-server-dark", dark: true) { model in
            model.applyFixture(.ready)
            model.settings.serverEnabled = true
            model.server.setPreviewForTesting(port: 8765, addresses: ["192.168.31.24"], code: "482913")
            model.panel = .settings
        },
        Shot(name: "08c-settings-server-light", dark: false) { model in
            model.applyFixture(.ready)
            model.settings.serverEnabled = true
            model.server.setPreviewForTesting(port: 8765, addresses: ["192.168.31.24"], code: nil)
            model.panel = .settings
        },
        Shot(name: "09-history-dark", dark: true) { model in
            model.applyFixture(.ready)
            model.panel = .history
        },
        Shot(name: "10-ready-light", dark: false) { model in
            model.applyFixture(.ready)
        },
        Shot(name: "11-big-preview-light", dark: false) { model in
            model.applyFixture(.ready)
            model.bigPreview = true
        },
        Shot(name: "12-idle-light", dark: false) { _ in },
    ]

    /// Рисует все состояния в PNG. Возвращает пути к файлам.
    @discardableResult
    public static func renderAll(to directory: URL) -> [URL] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []

        for shot in shots {
            let model = AppModel(settings: AppSettings(defaults: fixtureDefaults()),
                                 history: HistoryStore(fileURL: fixtureHistoryURL()))
            // В снимках движок не ищем — подставляем найденный, чтобы кнопка была в рабочем виде.
            model.setToolchainForTesting(Toolchain(
                ytdlp: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"),
                ffmpeg: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
                ytdlpVersion: "2026.07.04", ffmpegVersion: "7.1.1"))
            shot.build(model)

            let appearance = NSAppearance(named: shot.dark ? .darkAqua : .aqua)!
            var image: NSImage?
            appearance.performAsCurrentDrawingAppearance {
                let view = RootView(model: model)
                    .environment(\.ytvdSnapshot, true)
                    .environment(\.colorScheme, shot.dark ? .dark : .light)
                    .padding(24)
                    .background(Color(nsColor: NSColor(hex: shot.dark ? "3A3D42" : "B9BCC2")))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                image = renderer.nsImage
            }

            guard let image,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("не удалось отрисовать \(shot.name)\n".utf8))
                continue
            }
            let file = directory.appendingPathComponent("\(shot.name).png")
            try? png.write(to: file)
            written.append(file)
        }
        return written
    }

    private static func fixtureDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "studio.dk.ytvd.snapshots")!
        suite.removePersistentDomain(forName: "studio.dk.ytvd.snapshots")
        return suite
    }

    private static func fixtureHistoryURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ytvd-snapshot-history.json")
        try? FileManager.default.removeItem(at: url)
        let entries: [HistoryEntry] = [
            HistoryEntry(title: "Как устроен ffmpeg за 12 минут", quality: "1080p · MP4",
                         bytes: 333_447_168, path: "/tmp/a.mp4", source: .youtube,
                         date: Date().addingTimeInterval(-600)),
            HistoryEntry(title: "Lo-fi beats для работы", quality: "MP3 · 320",
                         bytes: 25_262_080, path: "/tmp/b.mp3", source: .youtube,
                         date: Date().addingTimeInterval(-86_400)),
            HistoryEntry(title: "Обзор Mac Studio M4 Ultra", quality: "2160p · MP4",
                         bytes: 1_535_115_264, path: "/tmp/c.mp4", source: .vimeo,
                         date: Date().addingTimeInterval(-90_000)),
            HistoryEntry(title: "Дока по Rutube API", quality: "720p · MP4",
                         bytes: 175_112_192, path: "/tmp/d.mp4", source: .rutube,
                         date: Date().addingTimeInterval(-3 * 86_400)),
            HistoryEntry(title: "Концерт в Зарядье", quality: "M4A · оригинал",
                         bytes: 60_817_408, path: "/tmp/e.m4a", source: .vk,
                         date: Date().addingTimeInterval(-8 * 86_400)),
        ]
        try? JSONEncoder().encode(entries).write(to: url)
        return url
    }
}

// MARK: - тестовые данные

extension AppModel {

    enum Fixture { case analyzing, ready, downloading, done, failed }

    /// Наполняет модель правдоподобными данными без обращения к сети.
    func applyFixture(_ fixture: Fixture) {
        let info = MediaInfo(
            id: "aqz-KE-bpKQ",
            title: "Big Buck Bunny — открытый анимационный фильм студии Blender",
            uploader: "Blender Foundation",
            duration: 632,
            thumbnails: [RawThumbnail(url: "https://example.invalid/hq.jpg", width: 1280, height: 720)],
            view_count: 4_213_884,
            upload_date: fixtureUploadDate(),
            formats: Self.fixtureFormats())

        setSourceForTesting(.youtube)
        urlText = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"

        switch fixture {
        case .analyzing:
            setStageForTesting(.analyzing, info: nil, options: [])

        case .ready:
            setOptionsForTesting(OptionBuilder.build(from: info), info: info)
            setThumbnailForTesting(Self.fixtureThumbnail())

        case .downloading:
            setOptionsForTesting(OptionBuilder.build(from: info), info: info)
            setThumbnailForTesting(Self.fixtureThumbnail())
            setProgressForTesting(DownloadProgress(downloaded: 82_837_504, total: 333_447_168,
                                                   speed: 12_960_890, eta: 19),
                                  phase: "видео")
            setStageForTesting(.downloading, info: info, options: options)

        case .done:
            setOptionsForTesting(OptionBuilder.build(from: info), info: info)
            setThumbnailForTesting(Self.fixtureThumbnail())
            setFinishedForTesting(file: URL(fileURLWithPath: "/tmp/Ролик [1080p].mp4"),
                                  bytes: 333_447_168, seconds: 26)

        case .failed:
            setStageForTesting(.failed, info: nil, options: [])
            setErrorForTesting("Ролик заблокирован в вашем регионе")
        }
    }

    private func fixtureUploadDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date().addingTimeInterval(-2 * 365 * 86_400))
    }

    private static func fixtureFormats() -> [RawFormat] {
        [
            RawFormat(format_id: "140", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2",
                      filesize: 10_276_045, tbr: 128, abr: 128),
            RawFormat(format_id: "251", ext: "webm", vcodec: "none", acodec: "opus",
                      filesize: 8_912_345, tbr: 112, abr: 112),
            RawFormat(format_id: "266", ext: "mp4", vcodec: "avc1.640033", acodec: "none",
                      height: 2160, fps: 30, filesize: 1_492_962_508, tbr: 18_200),
            RawFormat(format_id: "313", ext: "webm", vcodec: "vp09.00.50.08", acodec: "none",
                      height: 2160, fps: 30, filesize: 980_000_000, tbr: 12_400),
            RawFormat(format_id: "271", ext: "mp4", vcodec: "avc1.640032", acodec: "none",
                      height: 1440, fps: 30, filesize: 801_112_064, tbr: 9_600),
            RawFormat(format_id: "137", ext: "mp4", vcodec: "avc1.640028", acodec: "none",
                      height: 1080, fps: 30, filesize: 323_171_123, tbr: 4_100),
            RawFormat(format_id: "248", ext: "webm", vcodec: "vp09.00.40.08", acodec: "none",
                      height: 1080, fps: 30, filesize: 205_520_896, tbr: 2_600),
            RawFormat(format_id: "136", ext: "mp4", vcodec: "avc1.4d401f", acodec: "none",
                      height: 720, fps: 30, filesize: 165_100_355, tbr: 2_100),
            RawFormat(format_id: "395", ext: "mp4", vcodec: "av01.0.05M.08", acodec: "none",
                      height: 720, fps: 30, filesize: 83_886_080, tbr: 1_060),
            RawFormat(format_id: "135", ext: "mp4", vcodec: "avc1.4d401e", acodec: "none",
                      height: 480, fps: 30, filesize: 86_507_520, tbr: 1_100),
        ]
    }

    /// Синтетическая «обложка», чтобы карточка выглядела как настоящая.
    private static func fixtureThumbnail() -> NSImage {
        let size = NSSize(width: 640, height: 360)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor(hex: "4E6076"), NSColor(hex: "2A2F38"), NSColor(hex: "7A4F43")],
                   atLocations: [0, 0.55, 1], colorSpace: .sRGB)?
            .draw(in: NSRect(origin: .zero, size: size), angle: -35)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(ovalIn: NSRect(x: 250, y: 120, width: 140, height: 140)).fill()
        image.unlockFocus()
        return image
    }
}
