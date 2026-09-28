import XCTest
import YTVDAPI
@testable import VideoDownloader

/// Ответы сервера в том виде, в каком их отдаёт YTVD на Mac.
final class APIDecodingTests: XCTestCase {

    static let resolveJSON = """
    {"id":"aqz-KE-bpKQ","title":"Big Buck Bunny 60fps 4K","channel":"Blender","duration":635,
     "thumbnail":"https://i.ytimg.com/vi/aqz-KE-bpKQ/maxresdefault.jpg",
     "source_url":"https://www.youtube.com/watch?v=aqz-KE-bpKQ","platform":"youtube",
     "recommended_format_id":"h1080-60",
     "formats":[
      {"id":"h2160-60","label":"2160p60","width":3840,"height":2160,"fps":60,"codec":"hevc","container":"mp4",
       "has_video":true,"has_audio":true,"estimated_size":2392000000,"size_is_estimated":true,
       "needs_transcode":true,"details":"Исходник VP9 — iPhone его не играет, Mac перекодирует в HEVC аппаратно"},
      {"id":"h1080-60","label":"1080p60","width":1920,"height":1080,"fps":60,"codec":"h264","container":"mp4",
       "has_video":true,"has_audio":true,"estimated_size":268000000,"size_is_estimated":false,"needs_transcode":false},
      {"id":"h720-60","label":"720p60","width":1280,"height":720,"fps":60,"codec":"h264","container":"mp4",
       "has_video":true,"has_audio":true,"estimated_size":161000000,"size_is_estimated":false,"needs_transcode":false},
      {"id":"audio","label":"Только звук","codec":"aac","container":"m4a","has_video":false,"has_audio":true,
       "estimated_size":10000000,"size_is_estimated":false,"needs_transcode":false}
     ]}
    """

    func testResolveResponse() throws {
        let video = try API.decoder.decode(VideoInfo.self, from: Data(Self.resolveJSON.utf8))
        XCTAssertEqual(video.id, "aqz-KE-bpKQ")
        XCTAssertEqual(video.sourceUrl, "https://www.youtube.com/watch?v=aqz-KE-bpKQ")
        XCTAssertEqual(video.recommendedFormatId, "h1080-60")
        XCTAssertEqual(video.formats.count, 4)
        XCTAssertTrue(video.formats[0].needsTranscode)
        XCTAssertFalse(video.formats[3].hasVideo)
        XCTAssertNil(video.formats[3].height)
    }

    func testJobResponseWithDatesAndIndeterminateProgress() throws {
        let json = """
        {"job_id":"f4c79ac1","status":"merging","video_id":"aqz-KE-bpKQ","title":"Big Buck Bunny",
         "source_url":"https://www.youtube.com/watch?v=aqz-KE-bpKQ","format_id":"h1080-60",
         "format_label":"1080p60","created_at":"2026-09-27T23:36:31Z","updated_at":"2026-09-27T23:36:40Z"}
        """
        let job = try API.decoder.decode(JobInfo.self, from: Data(json.utf8))
        XCTAssertEqual(job.status, .merging)
        XCTAssertNil(job.progress, "склейка без прогресса — клиент крутит индикатор, а не показывает 100 %")
        XCTAssertEqual(job.createdAt.timeIntervalSince1970, 1_790_552_191)
    }

    func testUnknownFieldsAreIgnored() throws {
        // Новые поля в ответе сервера не должны ломать старое приложение.
        let json = #"{"name":"Mac","app_version":"1.3","api_version":"1","authorized":true,"ready":true,"something_new":42}"#
        let info = try API.decoder.decode(ServerInfo.self, from: Data(json.utf8))
        XCTAssertTrue(info.authorized)
        XCTAssertNil(info.ytdlpVersion)
    }

    func testServerErrorsBecomeHumanMessages() throws {
        let json = #"{"error":{"code":"private_video","message":"Это приватное видео"}}"#
        let body = try API.decoder.decode(APIErrorEnvelope.self, from: Data(json.utf8)).error
        let error = AppError.from(body)
        XCTAssertEqual(error.serverCode, "private_video")
        XCTAssertEqual(error.localizedDescription, "Это приватное видео")

        XCTAssertEqual(AppError.from(APIErrorBody(.unauthorized)), .unauthorized)
    }

    func testNetworkErrorsMeanMacUnavailable() {
        XCTAssertEqual(AppError.from(URLError(.cannotConnectToHost)), .serverUnavailable)
        XCTAssertEqual(AppError.from(URLError(.timedOut)), .serverUnavailable)
        XCTAssertTrue(AppError.serverUnavailable.localizedDescription.contains("YTVD"))
    }
}
