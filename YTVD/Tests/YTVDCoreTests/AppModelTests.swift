import XCTest
@testable import YTVDCore

@MainActor
final class AppModelTests: XCTestCase {

    private func makeModel() -> AppModel {
        let suite = UserDefaults(suiteName: "ytvd.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: suite)
        let history = HistoryStore(fileURL: URL(fileURLWithPath: "/tmp/ytvd-tests/\(UUID().uuidString).json"))
        return AppModel(settings: settings, history: history)
    }

    private func sampleOptions() -> [DownloadOption] {
        let info = MediaInfo(id: "abc", title: "Ролик", duration: 600,
                             thumbnails: [RawThumbnail(url: "https://i/1.jpg", width: 1280, height: 720)],
                             formats: [
            RawFormat(format_id: "140", ext: "m4a", vcodec: "none", acodec: "mp4a.40.2",
                      filesize: 10_000_000, tbr: 128, abr: 128),
            RawFormat(format_id: "266", ext: "mp4", vcodec: "avc1.640033", acodec: "none",
                      height: 2160, filesize: 1_400_000_000, tbr: 20_000),
            RawFormat(format_id: "137", ext: "mp4", vcodec: "avc1.640028", acodec: "none",
                      height: 1080, filesize: 320_000_000, tbr: 4_100),
            RawFormat(format_id: "136", ext: "mp4", vcodec: "avc1.4d401f", acodec: "none",
                      height: 720, filesize: 160_000_000, tbr: 2_100),
            RawFormat(format_id: "135", ext: "mp4", vcodec: "avc1.4d401e", acodec: "none",
                      height: 480, filesize: 90_000_000, tbr: 1_100),
        ])
        return OptionBuilder.build(from: info)
    }

    /// Подкладываем варианты, минуя сеть.
    private func load(_ model: AppModel, _ options: [DownloadOption]) {
        model.setOptionsForTesting(options)
    }

    func testDefaultSelectionMatchesPreferredQuality() {
        let model = makeModel()
        model.settings.defaultQuality = 1080
        load(model, sampleOptions())
        XCTAssertEqual(model.selectedOption?.height, 1080)
    }

    func testDefaultSelectionFallsBackBelowPreferredQuality() {
        let model = makeModel()
        model.settings.defaultQuality = 1440          // такого нет — берём ближайшее снизу
        load(model, sampleOptions())
        XCTAssertEqual(model.selectedOption?.height, 1080)
    }

    func testDefaultSelectionTakesSmallestWhenEverythingIsTooBig() {
        let model = makeModel()
        model.settings.defaultQuality = 240
        load(model, sampleOptions())
        XCTAssertEqual(model.selectedOption?.height, 480)
    }

    func testSizeLimitPicksLargestOptionThatFits() {
        let model = makeModel()
        model.settings.defaultQuality = 2160
        model.settings.limitFileSize = true
        model.settings.maxFileSizeMB = 200            // 200 МБ: проходит только 720p и 480p
        load(model, sampleOptions())
        XCTAssertEqual(model.selectedOption?.height, 720)
    }

    func testSizeLimitIsIgnoredWhenNothingFits() {
        let model = makeModel()
        model.settings.limitFileSize = true
        model.settings.maxFileSizeMB = 1
        load(model, sampleOptions())
        XCTAssertNotNil(model.selectedOption, "при недостижимом лимите всё равно нужно что-то выбрать")
    }

    func testCoverTogglesIndependentlyFromVideo() {
        let model = makeModel()
        load(model, sampleOptions())
        let videoBefore = model.selectedID
        model.select(model.coverOption!)
        XCTAssertTrue(model.coverSelected)
        XCTAssertEqual(model.selectedID, videoBefore, "выбор видео не должен сбрасываться")

        model.select(model.coverOption!)
        XCTAssertFalse(model.coverSelected)
    }

    func testSelectionBytesAddsCover() {
        let model = makeModel()
        load(model, sampleOptions())
        let videoOnly = model.selectionBytes
        model.select(model.coverOption!)
        XCTAssertGreaterThan(model.selectionBytes, videoOnly)
        XCTAssertEqual(model.selectionBytes, videoOnly + model.coverOption!.bytes)
    }

    func testArrowNavigationStaysInsideList() {
        let model = makeModel()
        load(model, sampleOptions())
        let list = model.visibleOptions.filter { $0.group != .cover }

        model.selectedID = list.first?.id
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedID, list.first?.id, "выше первой строки уходить некуда")

        model.selectedID = list.last?.id
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedID, list.last?.id, "ниже последней — тоже")
    }

    func testArrowNavigationSkipsCoverRow() {
        let model = makeModel()
        load(model, sampleOptions())
        let list = model.visibleOptions.filter { $0.group != .cover }
        model.selectedID = list[list.count - 1].id
        model.moveSelection(by: 1)
        XCTAssertNotEqual(model.selectedOption?.group, .cover)
    }

    func testAlternativesAreHiddenUntilRequested() {
        let model = makeModel()
        var options = sampleOptions()
        options.append(DownloadOption(id: "video-248", group: .video, tint: .orange,
                                      title: "1080p", subtitle: "VP9", bytes: 200_000_000,
                                      estimated: false, badge: nil, detail: "", hint: "",
                                      plan: DownloadPlan(mode: .video, selector: "248+251", container: "webm"),
                                      height: 1080))
        load(model, options)

        XCTAssertEqual(model.hiddenAlternatives, 1)
        XCTAssertFalse(model.visibleOptions.contains { $0.isAlternative })

        model.showAlternatives = true
        XCTAssertEqual(model.hiddenAlternatives, 0)
        XCTAssertTrue(model.visibleOptions.contains { $0.isAlternative })
    }

    func testClosedGroupHidesItsRows() {
        let model = makeModel()
        load(model, sampleOptions())
        model.toggleGroup(.audio)
        XCTAssertFalse(model.visibleOptions.contains { $0.group == .audio })
        model.toggleGroup(.audio)
        XCTAssertTrue(model.visibleOptions.contains { $0.group == .audio })
    }

    func testBlockWidthGrowsWithSizeAndKeepsMinimum() {
        let model = makeModel()
        load(model, sampleOptions())
        let sorted = model.options.sorted { $0.bytes < $1.bytes }
        let widths = sorted.map { model.blockWidth(for: $0) }

        XCTAssertEqual(widths, widths.sorted(), "длина плашки должна расти вместе с весом файла")
        XCTAssertGreaterThanOrEqual(widths.first ?? 0, 26, "самая мелкая плашка всё равно должна быть видна")
        XCTAssertLessThanOrEqual(widths.last ?? 0, Theme.Metrics.lane + 0.5, "плашка не должна вылезать за дорожку")
    }

    func testFileNameUsesTemplateAndTitle() {
        let model = makeModel()
        load(model, sampleOptions())
        model.settings.fileNameTemplate = "{title} [{quality}]"
        let name = model.makeBaseName(for: model.selectedOption)
        XCTAssertTrue(name.hasPrefix("Ролик ["), "получили: \(name)")
        XCTAssertTrue(name.contains("1080p"))
    }

    // MARK: - буфер обмена

    private func makeClipboardModel() -> (AppModel, NSPasteboard, ClipboardWatcher) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ytvd.test.\(UUID().uuidString)"))
        let watcher = ClipboardWatcher(pasteboard: pasteboard)
        let suite = UserDefaults(suiteName: "ytvd.tests.\(UUID().uuidString)")!
        let model = AppModel(settings: AppSettings(defaults: suite),
                             history: HistoryStore(fileURL: URL(fileURLWithPath: "/tmp/ytvd-tests/\(UUID().uuidString).json")),
                             clipboard: watcher)
        return (model, pasteboard, watcher)
    }

    /// Раньше подсказка жила во вложенном ObservableObject и до интерфейса не доходила.
    func testClipboardSuggestionReachesModel() {
        let (model, pasteboard, watcher) = makeClipboardModel()
        pasteboard.clearContents()
        pasteboard.setString("Смотри: https://youtu.be/abc123", forType: .string)

        watcher.start()
        defer { watcher.stop() }

        XCTAssertEqual(model.clipboardSuggestion?.absoluteString, "https://youtu.be/abc123")
    }

    func testUnsupportedLinkIsIgnored() {
        let (model, pasteboard, watcher) = makeClipboardModel()
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/video", forType: .string)

        watcher.start()
        defer { watcher.stop() }

        XCTAssertNil(model.clipboardSuggestion)
    }

    func testDismissedSuggestionDoesNotComeBack() {
        let (model, pasteboard, watcher) = makeClipboardModel()
        pasteboard.clearContents()
        pasteboard.setString("https://youtu.be/abc123", forType: .string)
        watcher.start()
        defer { watcher.stop() }

        XCTAssertNotNil(model.clipboardSuggestion)
        model.dismissClipboardSuggestion()
        XCTAssertNil(model.clipboardSuggestion)

        // Та же ссылка снова в буфере — повторно не предлагаем.
        pasteboard.clearContents()
        pasteboard.setString("https://youtu.be/abc123", forType: .string)
        watcher.start()
        XCTAssertNil(model.clipboardSuggestion)
    }

    func testWatcherIsSilentWhenDisabledInSettings() {
        let (model, pasteboard, watcher) = makeClipboardModel()
        model.settings.watchClipboard = false
        pasteboard.clearContents()
        pasteboard.setString("https://youtu.be/abc123", forType: .string)

        watcher.start()
        defer { watcher.stop() }

        XCTAssertNil(model.clipboardSuggestion)
    }

    /// Нажатие на логотип возвращает начальный экран — значит, снять нужно всё.
    func testResetReturnsToStartScreen() {
        let model = makeModel()
        load(model, sampleOptions())
        model.coverSelected = true
        model.showAlternatives = true
        model.bigPreview = true
        model.panel = .settings
        model.expandedID = model.options.first?.id
        model.toggleGroup(.audio)
        model.setClipboardSuggestionForTesting(URL(string: "https://youtu.be/abc"))

        model.reset()

        XCTAssertEqual(model.stage, .idle)
        XCTAssertTrue(model.options.isEmpty)
        XCTAssertNil(model.selectedID)
        XCTAssertNil(model.expandedID)
        XCTAssertNil(model.panel)
        XCTAssertNil(model.clipboardSuggestion)
        XCTAssertFalse(model.coverSelected)
        XCTAssertFalse(model.showAlternatives)
        XCTAssertFalse(model.bigPreview)
        XCTAssertTrue(model.urlText.isEmpty)
        XCTAssertTrue(model.queue.isEmpty)
        XCTAssertEqual(model.openGroups, [.video, .audio, .cover], "группы снова раскрыты")
    }

    /// Сорвалась загрузка — список качеств должен остаться, чтобы можно было повторить.
    func testFailedDownloadKeepsOptionsOnScreen() {
        let model = makeModel()
        load(model, sampleOptions())
        let selected = model.selectedID

        model.setErrorForTesting("Сервер раздачи видео отклонил соединение")

        XCTAssertEqual(model.stage, .ready, "варианты уже разобраны — экран не сбрасываем")
        XCTAssertFalse(model.options.isEmpty)
        XCTAssertEqual(model.selectedID, selected, "выбор сохраняется")
        XCTAssertNotNil(model.errorText)
    }

    func testFailedAnalysisShowsEmptyErrorScreen() {
        let model = makeModel()
        model.setErrorForTesting("Видео недоступно")
        XCTAssertEqual(model.stage, .failed, "разбирать нечего — показываем пустой экран с ошибкой")
        XCTAssertTrue(model.options.isEmpty)
    }

    func testResetFromErrorState() {
        let model = makeModel()
        model.setErrorForTesting("Видео недоступно")
        model.reset()
        XCTAssertEqual(model.stage, .idle)
        XCTAssertNil(model.errorText)
    }
}

@MainActor
final class HistoryStoreTests: XCTestCase {

    private func makeStore() -> HistoryStore {
        HistoryStore(fileURL: URL(fileURLWithPath: "/tmp/ytvd-tests/\(UUID().uuidString).json"), limit: 3)
    }

    func testKeepsNewestFirstAndTrimsToLimit() {
        let store = makeStore()
        for index in 1...5 {
            store.add(HistoryEntry(title: "Ролик \(index)", quality: "1080p", bytes: 1000,
                                   path: "/tmp/\(index).mp4", source: .youtube))
        }
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries.first?.title, "Ролик 5")
        XCTAssertEqual(store.entries.last?.title, "Ролик 3")
    }

    func testTotalBytes() {
        let store = makeStore()
        store.add(HistoryEntry(title: "A", quality: "", bytes: 100, path: "/a", source: .vk))
        store.add(HistoryEntry(title: "B", quality: "", bytes: 250, path: "/b", source: .vimeo))
        XCTAssertEqual(store.totalBytes, 350)
    }

    func testSurvivesReload() {
        let url = URL(fileURLWithPath: "/tmp/ytvd-tests/\(UUID().uuidString).json")
        let first = HistoryStore(fileURL: url)
        first.add(HistoryEntry(title: "Сохранённый", quality: "720p", bytes: 42,
                               path: "/tmp/x.mp4", source: .rutube))

        let second = HistoryStore(fileURL: url)
        XCTAssertEqual(second.entries.first?.title, "Сохранённый")
        XCTAssertEqual(second.entries.first?.source, .rutube)
        try? FileManager.default.removeItem(at: url)
    }

    func testClear() {
        let store = makeStore()
        store.add(HistoryEntry(title: "A", quality: "", bytes: 1, path: "/a", source: .youtube))
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {

    func testDefaults() {
        let suite = UserDefaults(suiteName: "ytvd.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: suite)
        XCTAssertEqual(settings.defaultQuality, 1080)
        XCTAssertTrue(settings.watchClipboard)
        XCTAssertFalse(settings.autoDownload)
        XCTAssertEqual(settings.fileNameTemplate, "{title} [{quality}]")
        XCTAssertEqual(settings.directory.lastPathComponent, "YTVD")
    }

    func testValuesPersistAcrossInstances() {
        let name = "ytvd.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        let first = AppSettings(defaults: suite)
        first.defaultQuality = 2160
        first.autoDownload = true

        let second = AppSettings(defaults: UserDefaults(suiteName: name)!)
        XCTAssertEqual(second.defaultQuality, 2160)
        XCTAssertTrue(second.autoDownload)
    }

    func testResetRestoresDefaults() {
        let suite = UserDefaults(suiteName: "ytvd.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: suite)
        settings.defaultQuality = 720
        settings.autoDownload = true
        settings.reset()
        XCTAssertEqual(settings.defaultQuality, 1080)
        XCTAssertFalse(settings.autoDownload)
    }
}
