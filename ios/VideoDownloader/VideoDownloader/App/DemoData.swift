#if DEBUG
import Foundation
import SwiftData
import YTVDAPI

/// Демо-данные для проверки интерфейса в симуляторе: запуск с аргументом -YTVDDemo.
/// Только в отладочной сборке — в приложение на iPhone не попадает.
///
/// Файлы demo-N.mp4 и demo-N.jpg кладутся в папки библиотеки снаружи
/// (xcrun simctl get_app_container …), здесь — только записи о них.
@MainActor
enum DemoData {

    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-YTVDDemo") }

    private struct Spec {
        let title: String
        let channel: String
        let duration: Double
        let label: String
        let size: Int64
        let platform: String
        let hoursAgo: Double
        let favorite: Bool
        var audio = false
    }

    private static let specs: [Spec] = [
        Spec(title: "Big Buck Bunny — открытый анимационный фильм студии Blender", channel: "Blender Foundation",
             duration: 90, label: "1080p60", size: 318_000_000, platform: "youtube", hoursAgo: 2, favorite: true),
        Spec(title: "Как устроен ffmpeg за 12 минут", channel: "Инженерный канал",
             duration: 90, label: "1080p", size: 148_000_000, platform: "youtube", hoursAgo: 5, favorite: false),
        Spec(title: "Обзор Mac Studio M4 Ultra: полгода в работе", channel: "Техника без пафоса",
             duration: 90, label: "2160p60", size: 1_430_000_000, platform: "youtube", hoursAgo: 26, favorite: true),
        Spec(title: "Концерт в Зарядье — живой звук", channel: "Филармония",
             duration: 90, label: "M4A", size: 58_000_000, platform: "vk", hoursAgo: 50, favorite: false, audio: true),
        Spec(title: "Дока по Rutube API: разбор примеров", channel: "Rutube для разработчиков",
             duration: 90, label: "720p", size: 167_000_000, platform: "rutube", hoursAgo: 80, favorite: false),
        Spec(title: "Timelapse: осенний лес за 30 секунд", channel: "Vimeo Staff Picks",
             duration: 90, label: "1080p", size: 92_000_000, platform: "vimeo", hoursAgo: 200, favorite: false),
    ]

    static func seed(_ context: ModelContext, positions: PlaybackPositions = .shared) {
        guard isEnabled, ((try? context.fetchCount(FetchDescriptor<VideoItem>())) ?? 0) == 0 else { return }
        var created: [VideoItem] = []
        for (index, spec) in specs.enumerated() {
            let number = index + 1
            let item = VideoItem(videoId: "demo-\(number)", title: spec.title, channel: spec.channel,
                                 duration: spec.duration, width: 1280, height: 720, fps: 30,
                                 formatLabel: spec.label, codec: spec.audio ? "aac" : "h264",
                                 isAudioOnly: spec.audio, fileName: "demo-\(number).mp4",
                                 thumbnailName: "demo-\(number).jpg", fileSize: spec.size,
                                 sourceURL: "https://example.com/demo-\(number)", platform: spec.platform,
                                 downloadedAt: Date(timeIntervalSinceNow: -spec.hoursAgo * 3600),
                                 isFavorite: spec.favorite)
            context.insert(item)
            created.append(item)
        }
        try? context.save()
        Playlists.create(name: "Вечер кино", items: [created[2], created[0], created[4]], in: context)
        Playlists.create(name: "Музыка", items: [created[3]], in: context)
        positions.record(37, duration: 90, for: created[0].id)
        positions.record(61, duration: 90, for: created[2].id)
    }

    static let video = VideoInfo(
        id: "aqz-KE-bpKQ", title: "Big Buck Bunny — открытый анимационный фильм студии Blender",
        channel: "Blender Foundation", duration: 635, thumbnail: demoThumbnail(1),
        sourceUrl: "https://www.youtube.com/watch?v=aqz-KE-bpKQ", platform: "youtube",
        formats: [
            format("h2160-60", "2160p60", 2160, 60, "hevc", 1_400_000_000, transcode: true),
            format("h1440-60", "1440p60", 1440, 60, "hevc", 774_000_000, transcode: true),
            format("h1080-60", "1080p60", 1080, 60, "h264", 318_000_000),
            format("h720-60", "720p60", 720, 60, "h264", 167_000_000),
            format("h480", "480p", 480, 30, "h264", 92_000_000),
            VideoFormat(id: "audio", label: "Только звук", codec: "aac", container: "m4a", hasVideo: false,
                        hasAudio: true, estimatedSize: 9_800_000, sizeIsEstimated: false, needsTranscode: false),
        ],
        recommendedFormatId: "h1080-60")

    /// Обложка «из сети» — та же демо-картинка с диска: AsyncImage читает и file://.
    private static func demoThumbnail(_ number: Int) -> String {
        LibraryFiles.thumbnails.appendingPathComponent("demo-\(number).jpg").absoluteString
    }

    private static func format(_ id: String, _ label: String, _ height: Int, _ fps: Int, _ codec: String,
                               _ size: Int64, transcode: Bool = false) -> VideoFormat {
        VideoFormat(id: id, label: label, width: height * 16 / 9, height: height, fps: fps, codec: codec,
                    container: "mp4", hasVideo: true, hasAudio: true, estimatedSize: size,
                    sizeIsEstimated: transcode, needsTranscode: transcode,
                    details: transcode ? "VP9 с YouTube → HEVC на Mac" : "H.264 + AAC без перекодирования")
    }

    static var transfer: Transfer {
        Transfer(id: UUID(), jobId: "demo", server: URL(string: "http://demo.invalid:8765")!,
                 video: VideoInfo(id: "demo-t", title: "Lo-fi beats для работы — 2 часа", channel: "Lo-fi Radio",
                                  duration: 7200, thumbnail: demoThumbnail(5), sourceUrl: "https://example.com/t",
                                  platform: "youtube", formats: [], recommendedFormatId: nil),
                 format: format("h720", "720p", 720, 30, "h264", 483_000_000),
                 phase: .transfer, received: 356_000_000, expected: 483_000_000, speed: 12_400_000)
    }
}

extension DownloadModel {
    /// Разобранный ролик без сервера — только для демо.
    func showDemo(_ video: VideoInfo) {
        text = video.sourceUrl
        showReadyForDemo(video)
        selectedFormatId = video.recommendedFormatId
    }
}
#endif
