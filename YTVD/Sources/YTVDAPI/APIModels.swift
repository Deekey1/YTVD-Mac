import Foundation

/// Контракт между сервером на Mac и приложением на iPhone.
///
/// iPhone ничего не знает о yt-dlp: он видит только эти модели. Поэтому бэкенд
/// можно будет перенести на VPS, не трогая клиент.
public enum API {
    public static let version = "1"
    public static let basePath = "/api/v1"
    /// Тип Bonjour-сервиса. Длина имени ограничена 15 символами.
    public static let bonjourType = "_ytvd._tcp"
    public static let defaultPort: UInt16 = 8765

    /// JSON в стиле snake_case, даты — ISO 8601.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - разбор ссылки

public struct ResolveRequest: Codable, Sendable, Equatable {
    public var url: String
    public init(url: String) { self.url = url }
}

/// Вариант качества в том виде, в каком его видит пользователь: без номеров
/// форматов yt-dlp, без кодеков и контейнеров.
public struct VideoFormat: Codable, Sendable, Hashable, Identifiable {
    /// Стабильный идентификатор: «h1080», «h2160-60», «audio». Не номер формата yt-dlp.
    public var id: String
    /// «1080p», «2160p60», «Только звук».
    public var label: String
    public var width: Int?
    public var height: Int?
    public var fps: Int?
    /// Кодек итогового файла: h264, hevc, aac.
    public var codec: String
    public var container: String
    public var hasVideo: Bool
    public var hasAudio: Bool
    public var estimatedSize: Int64?
    /// Размер прикинут по битрейту, а не взят из ответа площадки.
    public var sizeIsEstimated: Bool
    /// Итог будет перекодирован на сервере — дольше, но играет на любом iPhone.
    public var needsTranscode: Bool
    /// Подробности для экрана «Детали».
    public var details: String?

    public init(id: String, label: String, width: Int? = nil, height: Int? = nil, fps: Int? = nil,
                codec: String, container: String, hasVideo: Bool, hasAudio: Bool,
                estimatedSize: Int64?, sizeIsEstimated: Bool, needsTranscode: Bool,
                details: String? = nil) {
        self.id = id; self.label = label; self.width = width; self.height = height
        self.fps = fps; self.codec = codec; self.container = container
        self.hasVideo = hasVideo; self.hasAudio = hasAudio
        self.estimatedSize = estimatedSize; self.sizeIsEstimated = sizeIsEstimated
        self.needsTranscode = needsTranscode; self.details = details
    }
}

public struct VideoInfo: Codable, Sendable, Equatable {
    /// Идентификатор ролика на площадке — по нему iPhone ищет дубликаты.
    public var id: String
    public var title: String
    public var channel: String?
    public var duration: Double?
    public var thumbnail: String?
    public var sourceUrl: String
    public var platform: String
    public var formats: [VideoFormat]
    /// Что предложить по умолчанию.
    public var recommendedFormatId: String?

    public init(id: String, title: String, channel: String?, duration: Double?,
                thumbnail: String?, sourceUrl: String, platform: String,
                formats: [VideoFormat], recommendedFormatId: String?) {
        self.id = id; self.title = title; self.channel = channel; self.duration = duration
        self.thumbnail = thumbnail; self.sourceUrl = sourceUrl; self.platform = platform
        self.formats = formats; self.recommendedFormatId = recommendedFormatId
    }
}

// MARK: - задания

public struct DownloadRequest: Codable, Sendable, Equatable {
    public var url: String
    public var formatId: String
    public init(url: String, formatId: String) { self.url = url; self.formatId = formatId }
}

public enum JobStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case resolving
    case downloadingVideo = "downloading_video"
    case downloadingAudio = "downloading_audio"
    case merging
    case transcoding
    case ready
    case failed
    case cancelled
    /// Сервер перезапустился посреди работы — задание не довести, но и не «вечные 63 %».
    case interrupted

    public var isFinished: Bool {
        switch self {
        case .ready, .failed, .cancelled, .interrupted: true
        default: false
        }
    }

    /// Русское название этапа для интерфейса.
    public var title: String {
        switch self {
        case .queued: "В очереди"
        case .resolving: "Разбор ссылки"
        case .downloadingVideo: "Скачивание видео"
        case .downloadingAudio: "Скачивание звука"
        case .merging: "Объединение видео и аудио…"
        case .transcoding: "Перекодирование для iPhone"
        case .ready: "Готово"
        case .failed: "Ошибка"
        case .cancelled: "Отменено"
        case .interrupted: "Прервано перезапуском сервера"
        }
    }
}

public struct JobInfo: Codable, Sendable, Equatable, Identifiable {
    public var jobId: String
    public var status: JobStatus
    /// Доля текущего этапа 0…1. Нет значения — этап без понятного прогресса (склейка).
    public var progress: Double?
    public var downloadedBytes: Int64?
    public var totalBytes: Int64?
    /// Байт в секунду.
    public var speed: Double?
    /// Секунд до конца этапа.
    public var eta: Int?
    public var error: APIErrorBody?
    public var filename: String?
    public var fileSize: Int64?
    public var videoId: String
    public var title: String
    public var channel: String?
    public var duration: Double?
    public var thumbnail: String?
    public var sourceUrl: String
    public var formatId: String
    public var formatLabel: String
    public var height: Int?
    public var createdAt: Date
    public var updatedAt: Date

    public var id: String { jobId }

    public init(jobId: String, status: JobStatus, progress: Double? = nil,
                downloadedBytes: Int64? = nil, totalBytes: Int64? = nil, speed: Double? = nil,
                eta: Int? = nil, error: APIErrorBody? = nil, filename: String? = nil,
                fileSize: Int64? = nil, videoId: String, title: String, channel: String? = nil,
                duration: Double? = nil, thumbnail: String? = nil, sourceUrl: String,
                formatId: String, formatLabel: String, height: Int? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.jobId = jobId; self.status = status; self.progress = progress
        self.downloadedBytes = downloadedBytes; self.totalBytes = totalBytes
        self.speed = speed; self.eta = eta; self.error = error; self.filename = filename
        self.fileSize = fileSize; self.videoId = videoId; self.title = title
        self.channel = channel; self.duration = duration; self.thumbnail = thumbnail
        self.sourceUrl = sourceUrl; self.formatId = formatId; self.formatLabel = formatLabel
        self.height = height; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct JobList: Codable, Sendable {
    public var jobs: [JobInfo]
    public init(jobs: [JobInfo]) { self.jobs = jobs }
}

// MARK: - сервер и сопряжение

public struct ServerInfo: Codable, Sendable, Equatable {
    public var name: String
    public var appVersion: String
    public var apiVersion: String
    /// Запрос пришёл с действующим токеном. Без него версии инструментов не раскрываем.
    public var authorized: Bool
    public var ready: Bool
    public var ytdlpVersion: String?
    public var ffmpegVersion: String?
    public var jsRuntime: String?
    public var freeSpace: Int64?
    /// Все адреса этого Mac вида «http://192.168.1.10:8765» — в домашней сети и в Tailscale.
    /// iPhone запоминает их и сам переключается, когда уходит из дома. Только своим.
    public var addresses: [String]?

    public init(name: String, appVersion: String, apiVersion: String, authorized: Bool,
                ready: Bool, ytdlpVersion: String? = nil, ffmpegVersion: String? = nil,
                jsRuntime: String? = nil, freeSpace: Int64? = nil, addresses: [String]? = nil) {
        self.name = name; self.appVersion = appVersion; self.apiVersion = apiVersion
        self.authorized = authorized; self.ready = ready; self.ytdlpVersion = ytdlpVersion
        self.ffmpegVersion = ffmpegVersion; self.jsRuntime = jsRuntime; self.freeSpace = freeSpace
        self.addresses = addresses
    }
}

public struct PairRequest: Codable, Sendable, Equatable {
    public var code: String
    public var deviceName: String
    public init(code: String, deviceName: String) { self.code = code; self.deviceName = deviceName }
}

public struct PairResponse: Codable, Sendable, Equatable {
    public var token: String
    public var serverName: String
    public init(token: String, serverName: String) { self.token = token; self.serverName = serverName }
}

// MARK: - движок

/// Итог обновления yt-dlp на Mac по просьбе iPhone.
public struct EngineUpdateResult: Codable, Sendable, Equatable {
    public var updated: Bool
    public var version: String?
    public var message: String

    public init(updated: Bool, version: String?, message: String) {
        self.updated = updated; self.version = version; self.message = message
    }

    public static func upToDate(_ version: String?) -> EngineUpdateResult {
        EngineUpdateResult(updated: false, version: version,
                           message: version.map { "Движок уже свежий — версия \($0)" } ?? "Движок уже свежий")
    }
}

// MARK: - ошибки

/// Машиночитаемый код плюс человеческий текст. Технические подробности остаются в журнале сервера.
public struct APIErrorBody: Codable, Sendable, Equatable, Error {
    public var code: String
    public var message: String
    public init(code: String, message: String) { self.code = code; self.message = message }
    public init(_ code: APIErrorCode, _ message: String? = nil) {
        self.code = code.rawValue
        self.message = message ?? code.defaultMessage
    }
}

public struct APIErrorEnvelope: Codable, Sendable {
    public var error: APIErrorBody
    public init(error: APIErrorBody) { self.error = error }
}

public enum APIErrorCode: String, Codable, Sendable, CaseIterable {
    case badRequest = "bad_request"
    case invalidUrl = "invalid_url"
    case unauthorized
    case pairingFailed = "pairing_failed"
    case rateLimited = "rate_limited"
    case videoUnavailable = "video_unavailable"
    case privateVideo = "private_video"
    case ageRestricted = "age_restricted"
    case authenticationRequired = "authentication_required"
    case blocked
    case formatUnavailable = "format_unavailable"
    case networkError = "network_error"
    case notEnoughStorage = "not_enough_storage"
    case ffmpegError = "ffmpeg_error"
    case engineOutdated = "engine_outdated"
    case jobNotFound = "job_not_found"
    case notReady = "not_ready"
    case cancelled
    case serverError = "server_error"

    public var defaultMessage: String {
        switch self {
        case .badRequest: "Некорректный запрос"
        case .invalidUrl: "Ссылка выглядит неправильно"
        case .unauthorized: "Нужно сопряжение с Mac"
        case .pairingFailed: "Неверный или устаревший код сопряжения"
        case .rateLimited: "Слишком много попыток — подождите немного"
        case .videoUnavailable: "Видео недоступно"
        case .privateVideo: "Это приватное видео"
        case .ageRestricted: "Возрастное ограничение — нужен вход в аккаунт"
        case .authenticationRequired: "Площадка требует входа в аккаунт"
        case .blocked: "Площадка не пускает с адреса Mac"
        case .formatUnavailable: "Такого качества у ролика нет"
        case .networkError: "Нет связи с площадкой"
        case .notEnoughStorage: "Недостаточно свободного места"
        case .ffmpegError: "Не удалось собрать видео со звуком"
        case .engineOutdated: "Движок на Mac устарел — обновите его в YTVD"
        case .jobNotFound: "Задание не найдено — возможно, сервер перезапускался"
        case .notReady: "Файл ещё не готов"
        case .cancelled: "Отменено"
        case .serverError: "Ошибка на сервере"
        }
    }
}
