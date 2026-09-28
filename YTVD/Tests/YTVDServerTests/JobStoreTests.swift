import XCTest
@testable import YTVDCore

final class JobStoreTests: XCTestCase {

    private let url = "https://www.youtube.com/watch?v=aqz-KE-bpKQ"

    private func makeStore(_ shared: FakeEngine.Shared, directory: URL = Fixtures.temporaryDirectory(),
                           maxConcurrent: Int = 1, freeSpace: Int64? = nil) -> JobStore {
        JobStore(config: .init(directory: directory, maxConcurrent: maxConcurrent),
                 makeEngine: { FakeEngine(shared) },
                 freeSpace: { _ in freeSpace },
                 thumbnailProbe: { _ in true })
    }

    private func waitFor(_ store: JobStore, _ id: String, _ status: JobStatus,
                         timeout: TimeInterval = 5) async throws -> JobInfo {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let job = await store.job(id), job.status == status { return job }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let current = await store.job(id)?.status.rawValue ?? "нет задания"
        XCTFail("не дождались \(status.rawValue), сейчас \(current)")
        throw CancellationError()
    }

    func testResolveNormalizesAndCaches() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        let store = makeStore(shared)

        let video = try await store.resolve(url: url)
        XCTAssertEqual(video.id, "aqz-KE-bpKQ")
        XCTAssertEqual(video.formats.first?.label, "2160p60")
        XCTAssertEqual(video.recommendedFormatId, "h1080-60")
        XCTAssertEqual(video.platform, "youtube")

        _ = try await store.resolve(url: url)
        XCTAssertEqual(shared.resolves, 1, "повторный разбор той же ссылки берётся из памяти")
    }

    /// У многих роликов нет maxresdefault и hq720 — берём лучшую из живых, а не первую из списка.
    func testThumbnailSkipsMissingSizes() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        let store = JobStore(config: .init(directory: Fixtures.temporaryDirectory()),
                             makeEngine: { FakeEngine(shared) }, freeSpace: { _ in nil },
                             thumbnailProbe: { $0.contains("hqdefault") || $0.contains("sddefault") })
        let video = try await store.resolve(url: url)
        XCTAssertEqual(video.thumbnail?.hasSuffix("/sddefault.jpg"), true, video.thumbnail ?? "нет обложки")
    }

    /// Из «Поделиться» ссылка приходит дважды почти одновременно — yt-dlp должен отработать один раз.
    func testConcurrentResolvesShareOneEngineRun() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        shared.resolveDelay = 200_000_000
        let store = makeStore(shared)
        async let first = store.resolve(url: url)
        async let second = store.resolve(url: url)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a, b)
        XCTAssertEqual(shared.resolves, 1, "вторая копия ссылки ждёт первую, а не запускает разбор заново")
    }

    func testInvalidURLIsRejectedBeforeEngine() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        let store = makeStore(shared)
        do {
            _ = try await store.resolve(url: "https://example.com/video")
            XCTFail("ожидали отказ")
        } catch let error as APIErrorBody {
            XCTAssertEqual(error.code, APIErrorCode.invalidUrl.rawValue)
        }
        XCTAssertEqual(shared.resolves, 0, "в yt-dlp чужие ссылки не отправляем")
    }

    func testDownloadGoesThroughStagesToReady() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        let store = makeStore(shared)

        let job = try await store.startDownload(url: url, formatId: "h1080-60")
        XCTAssertEqual(job.status, .queued)
        XCTAssertEqual(job.formatLabel, "1080p60")

        let ready = try await waitFor(store, job.jobId, .ready)
        XCTAssertEqual(ready.progress, 1)
        XCTAssertEqual(ready.fileSize, 4096)
        XCTAssertEqual(ready.filename, "Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film [1080p60].mp4")

        let stored = await store.file(job.jobId)
        let file = try XCTUnwrap(stored)
        XCTAssertEqual(file.url.lastPathComponent, "\(job.jobId).mp4", "на диске — по идентификатору, не по названию")
        XCTAssertEqual(shared.transcodes, 0, "1080p есть в H.264 — перекодирования нет")
    }

    func testHighResolutionIsTranscoded() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        let store = makeStore(shared)
        let job = try await store.startDownload(url: url, formatId: "h2160-60")
        _ = try await waitFor(store, job.jobId, .ready)
        XCTAssertEqual(shared.transcodes, 1)
        let stored = await store.file(job.jobId)
        XCTAssertEqual(try XCTUnwrap(stored).url.pathExtension, "mp4")
    }

    func testUnknownFormatIsRejected() async throws {
        let store = makeStore(FakeEngine.Shared(info: try Fixtures.youtube4K()))
        do {
            _ = try await store.startDownload(url: url, formatId: "137+140")
            XCTFail("номера форматов yt-dlp снаружи не принимаем")
        } catch let error as APIErrorBody {
            XCTAssertEqual(error.code, APIErrorCode.formatUnavailable.rawValue)
        }
    }

    func testEngineFailureBecomesHumanError() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        shared.failDownload = YTVDError.tool("Видео недоступно")
        let store = makeStore(shared)
        let job = try await store.startDownload(url: url, formatId: "h720-60")
        let failed = try await waitFor(store, job.jobId, .failed)
        XCTAssertEqual(failed.error?.code, APIErrorCode.videoUnavailable.rawValue)
        XCTAssertEqual(failed.error?.message, "Видео недоступно")
    }

    func testOnlyOneJobRunsAtATime() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        shared.released = false
        let store = makeStore(shared, maxConcurrent: 1)

        let first = try await store.startDownload(url: url, formatId: "h720-60")
        let second = try await store.startDownload(url: url, formatId: "h480")
        _ = try await waitFor(store, first.jobId, .downloadingVideo)
        let waiting = await store.job(second.jobId)?.status
        XCTAssertEqual(waiting, .queued, "второе ждёт, пока первое не закончится")

        shared.released = true
        _ = try await waitFor(store, first.jobId, .ready)
        _ = try await waitFor(store, second.jobId, .ready)
    }

    func testCancelQueuedAndRunning() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        shared.released = false
        let store = makeStore(shared)

        let running = try await store.startDownload(url: url, formatId: "h720-60")
        let queued = try await store.startDownload(url: url, formatId: "h480")
        _ = try await waitFor(store, running.jobId, .downloadingVideo)

        await store.cancel(queued.jobId)
        let queuedStatus = await store.job(queued.jobId)?.status
        XCTAssertEqual(queuedStatus, .cancelled)

        await store.cancel(running.jobId)
        let immediately = await store.job(running.jobId)?.status
        XCTAssertEqual(immediately, .cancelled, "отмена видна сразу, не дожидаясь остановки процесса")
        _ = try await waitFor(store, running.jobId, .cancelled)
        try await Task.sleep(nanoseconds: 100_000_000)
        let settled = await store.job(running.jobId)?.status
        XCTAssertEqual(settled, .cancelled, "остановленный движок не превращает отмену в ошибку")
    }

    /// Сервер перезапустился посреди загрузки — никаких «вечных 63 %».
    func testRestartKeepsReadyAndMarksUnfinishedInterrupted() async throws {
        let directory = Fixtures.temporaryDirectory()
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())

        let store = makeStore(shared, directory: directory)
        let done = try await store.startDownload(url: url, formatId: "h720-60")
        _ = try await waitFor(store, done.jobId, .ready)

        shared.released = false
        let pending = try await store.startDownload(url: url, formatId: "h480")
        _ = try await waitFor(store, pending.jobId, .downloadingVideo)

        let restarted = makeStore(shared, directory: directory)
        let doneStatus = await restarted.job(done.jobId)?.status
        let pendingJob = await restarted.job(pending.jobId)
        XCTAssertEqual(doneStatus, .ready, "готовый файл никуда не делся")
        XCTAssertEqual(pendingJob?.status, .interrupted)
        XCTAssertNotNil(pendingJob?.error, "у прерванного есть понятная причина")
        shared.released = true
    }

    func testNotEnoughSpaceOnMac() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        let store = makeStore(shared, freeSpace: 10 * 1024 * 1024)       // 10 МБ свободно
        let job = try await store.startDownload(url: url, formatId: "h1080-60")
        let failed = try await waitFor(store, job.jobId, .failed)
        XCTAssertEqual(failed.error?.code, APIErrorCode.notEnoughStorage.rawValue)
    }

    func testDeleteRemovesFile() async throws {
        let store = makeStore(FakeEngine.Shared(info: try Fixtures.youtube4K()))
        let job = try await store.startDownload(url: url, formatId: "h720-60")
        _ = try await waitFor(store, job.jobId, .ready)
        let stored = await store.file(job.jobId)
        let file = try XCTUnwrap(stored).url

        await store.delete(job.jobId)
        let gone = await store.job(job.jobId)
        XCTAssertNil(gone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testWaitReturnsAsSoonAsReady() async throws {
        let shared = FakeEngine.Shared(info: try Fixtures.youtube4K())
        shared.released = false
        let store = makeStore(shared)
        let job = try await store.startDownload(url: url, formatId: "h720-60")

        Task { try await Task.sleep(nanoseconds: 300_000_000); shared.released = true }
        let finished = await store.waitUntilFinished(job.jobId, timeout: 10)
        XCTAssertEqual(finished?.status, .ready)
    }

    func testAdviceNamesTheMac() {
        let body = JobStore.apiError(from: YTVDError.tool(
            "YouTube требует подтвердить, что вы не робот. Включите в настройках «Брать cookies из браузера» — обычно этого хватает."))
        XCTAssertEqual(body.code, APIErrorCode.authenticationRequired.rawValue)
        XCTAssertTrue(body.message.contains("на Mac в настройках YTVD"), "на iPhone таких настроек нет")
    }

    func testErrorMapping() {
        let cases: [(YTVDError, APIErrorCode)] = [
            (.tool("Это приватное видео"), .privateVideo),
            (.tool("Возрастное ограничение — нужен вход в аккаунт"), .ageRestricted),
            (.tool("Площадка заблокировала адрес — обычно так отсекают VPN"), .blocked),
            (.tool("Такого формата у ролика нет — попробуйте другое качество"), .formatUnavailable),
            (.engineStale("YouTube не отдал ни одного формата"), .engineOutdated),
            (.network("Нет связи"), .networkError),
            (.cancelled, .cancelled),
        ]
        for (error, code) in cases {
            XCTAssertEqual(JobStore.apiError(from: error).code, code.rawValue, "\(error)")
        }
    }
}
