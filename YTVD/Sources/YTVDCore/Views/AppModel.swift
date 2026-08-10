import AppKit
import Combine
import SwiftUI

/// Состояние всего приложения и переходы между экранами.
@MainActor
public final class AppModel: ObservableObject {

    public enum Stage: Equatable {
        case idle           // ждём ссылку
        case analyzing      // спрашиваем yt-dlp
        case ready          // показываем варианты
        case downloading
        case done
        case failed
    }

    public enum Panel: Equatable { case settings, history }

    public struct Finished: Equatable {
        public let file: URL
        public let bytes: Int64
        public let seconds: Int
    }

    public struct QueueItem: Identifiable, Equatable {
        public let id = UUID()
        public let url: URL
        public var title: String?
        public var source: MediaSource
    }

    // MARK: - публикуемое состояние

    @Published public private(set) var stage: Stage = .idle
    @Published public var urlText: String = ""
    @Published public private(set) var info: MediaInfo?
    @Published public private(set) var source: MediaSource = .other
    @Published public private(set) var options: [DownloadOption] = []
    @Published public var selectedID: String?
    @Published public var coverSelected = false
    @Published public var expandedID: String?
    @Published public var showAlternatives = false
    @Published public var openGroups: Set<DownloadOption.Group> = [.video, .audio, .cover]
    @Published public private(set) var progress: DownloadProgress?
    @Published public private(set) var phaseText: String = ""
    @Published public private(set) var errorText: String?
    @Published public private(set) var finished: Finished?
    @Published public private(set) var thumbnail: NSImage?
    @Published public var bigPreview = false
    @Published public private(set) var toolchain = Toolchain()
    @Published public private(set) var queue: [QueueItem] = []
    @Published public var panel: Panel?
    @Published public private(set) var coverSavedAt: URL?
    /// Ссылка, замеченная в буфере обмена. Держим её здесь, а не в наблюдателе:
    /// изменения вложенного ObservableObject до интерфейса не доходят.
    @Published public private(set) var clipboardSuggestion: URL?
    /// Вышедшее обновление движка. Появляется только после подходящего сбоя.
    @Published public private(set) var engineUpdate: EngineUpdater.Available?
    @Published public private(set) var engineUpdating = false
    @Published public private(set) var engineNote: String?

    public let settings: AppSettings
    public let history: HistoryStore
    public let clipboard: ClipboardWatcher

    private var service: MediaService?
    private var job: Task<Void, Never>?
    private var currentURL: URL?
    private var startedAt: Date?

    // Значения по умолчанию создаём в теле: выражения в списке параметров
    // вычисляются вне главного актора и не проходят проверку изоляции.
    public init(settings: AppSettings? = nil,
                history: HistoryStore? = nil,
                clipboard: ClipboardWatcher? = nil) {
        let clipboardWatcher = clipboard ?? ClipboardWatcher()
        self.settings = settings ?? AppSettings()
        self.history = history ?? HistoryStore()
        self.clipboard = clipboardWatcher
        clipboardWatcher.onDetect = { [weak self] url in self?.clipboardFound(url) }
    }

    // MARK: - запуск

    public func bootstrap() async {
        let chain = await Toolchain.discover()
        toolchain = chain
        service = MediaService(toolchain: chain)
        if settings.watchClipboard { clipboard.start() }
        if !chain.isReady {
            errorText = "Не найден yt-dlp. Установите его: brew install yt-dlp"
            stage = .failed
        }
    }

    public func refreshToolchain() async {
        let chain = await Toolchain.discover()
        toolchain = chain
        service = MediaService(toolchain: chain)
        if chain.isReady, stage == .failed, info == nil { reset() }
    }

    // MARK: - варианты, доступные для показа и выбора

    /// Строки в том порядке, в котором они видны на экране.
    public var visibleOptions: [DownloadOption] {
        options.filter { option in
            guard openGroups.contains(option.group) else { return false }
            return showAlternatives || !option.isAlternative
        }
    }

    public var hiddenAlternatives: Int {
        showAlternatives ? 0 : options.filter(\.isAlternative).count
    }

    /// Подпись строки «ещё N»: если у экономных кодеков есть разрешения выше основных —
    /// говорим именно об этом, иначе о весе.
    public var alternativesLabel: String {
        let alternatives = options.filter(\.isAlternative)
        let mainMax = options.filter { $0.group == .video && !$0.isAlternative }
            .compactMap(\.height).max() ?? 0
        let altMax = alternatives.compactMap(\.height).max() ?? 0
        return altMax > mainMax
            ? "ещё \(alternatives.count): VP9 / AV1 — до \(altMax)p"
            : "ещё \(alternatives.count): VP9 / AV1 — легче по весу"
    }

    public var selectedOption: DownloadOption? {
        options.first { $0.id == selectedID }
    }

    public var coverOption: DownloadOption? {
        options.first { $0.group == .cover }
    }

    /// Чего не хватает в системе. Предупреждаем заранее, а не после неудачной попытки.
    public var missingTool: (message: String, command: String)? {
        if !toolchain.canSolveYouTube {
            return ("Не найден Deno. Без него YouTube не отдаёт форматы — остальные "
                    + "площадки работают.", "brew install deno")
        }
        if !toolchain.canMerge {
            return ("Не найден ffmpeg: доступны только готовые файлы со звуком, "
                    + "без выбора качества и без MP3.", "brew install ffmpeg")
        }
        return nil
    }

    /// Сколько всего весит выбранное.
    public var selectionBytes: Int64 {
        (selectedOption?.bytes ?? 0) + (coverSelected ? (coverOption?.bytes ?? 0) : 0)
    }

    /// Самая длинная плашка задаёт масштаб дорожки.
    public var scaleMaximum: Int64 {
        max(1, options.map(\.bytes).max() ?? 1)
    }

    /// Длина плашки: корневая шкала, чтобы мелкие файлы не схлопывались в точку.
    public func blockWidth(for option: DownloadOption) -> CGFloat {
        let ratio = sqrt(Double(max(0, option.bytes))) / sqrt(Double(scaleMaximum))
        return max(26, CGFloat(ratio) * Theme.Metrics.lane)
    }

    public func rulerTicks() -> [(x: CGFloat, label: String)] {
        let maximum = Double(scaleMaximum)
        let candidates: [Double] = [10, 100, 400, 1200].map { $0 * 1024 * 1024 }
        // Идём справа налево: верхняя метка задаёт масштаб, её сохраняем в первую очередь.
        var ticks: [(x: CGFloat, label: String)] = []
        var previousLabelX: CGFloat = .greatestFiniteMagnitude
        for value in candidates.reversed() {
            guard value < maximum else { continue }
            let x = CGFloat(sqrt(value) / sqrt(maximum)) * Theme.Metrics.lane
            let labelX = x > Theme.Metrics.lane - 48 ? x - 46 : x       // у края подпись уходит влево
            guard previousLabelX - labelX >= 56 else { continue }        // подписи не должны наезжать
            ticks.append((x, Fmt.bytes(Int64(value))))
            previousLabelX = labelX
        }
        return ticks.reversed()
    }

    // MARK: - выбор

    public func select(_ option: DownloadOption) {
        if option.group == .cover {
            coverSelected.toggle()
        } else {
            selectedID = option.id
        }
    }

    public func toggleExpanded(_ option: DownloadOption) {
        expandedID = expandedID == option.id ? nil : option.id
    }

    public func toggleGroup(_ group: DownloadOption.Group) {
        if openGroups.contains(group) { openGroups.remove(group) } else { openGroups.insert(group) }
    }

    /// ↑/↓ по списку.
    public func moveSelection(by delta: Int) {
        let list = visibleOptions.filter { $0.group != .cover }
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(0, index + delta), list.count - 1)
        selectedID = list[next].id
    }

    /// Выбор по умолчанию: ближайшее качество из настроек, с оглядкой на лимит размера.
    func applyDefaultSelection() {
        let videos = options.filter { $0.group == .video && !$0.isAlternative }
        guard !videos.isEmpty else {
            selectedID = options.first { $0.group == .audio }?.id ?? options.first?.id
            return
        }

        var candidates = videos
        if settings.limitFileSize {
            let limit = Int64(settings.maxFileSizeMB) * 1024 * 1024
            let underLimit = videos.filter { $0.bytes <= limit }
            if !underLimit.isEmpty { candidates = underLimit }
        }

        let target = settings.defaultQuality
        // Предпочитаем качество не выше заданного; если таких нет — берём минимальное доступное.
        let notAbove = candidates.filter { ($0.height ?? 0) <= target }
        let best = notAbove.max { ($0.height ?? 0) < ($1.height ?? 0) }
            ?? candidates.min { ($0.height ?? 0) < ($1.height ?? 0) }
        selectedID = best?.id
        coverSelected = settings.saveCoverAlongside
    }

    // MARK: - анализ ссылки

    private func clipboardFound(_ url: URL) {
        guard settings.watchClipboard else { return }
        if stage == .downloading {
            enqueue(url)
        } else if settings.autoDownload {
            analyze(url, autoStart: true)
        } else {
            // Показываем полоску «в буфере» — решение за пользователем.
            clipboardSuggestion = url
        }
    }

    public func acceptClipboardSuggestion() {
        guard let url = clipboardSuggestion else { return }
        analyze(url, autoStart: settings.autoDownload)
    }

    public func dismissClipboardSuggestion() {
        if let url = clipboardSuggestion { clipboard.consume(url) }
        clipboardSuggestion = nil
    }

    public func submitTypedURL() {
        guard let url = LinkDetector.normalize(urlText) else {
            errorText = "Ссылка выглядит неправильно"
            stage = .failed
            return
        }
        analyze(url, autoStart: settings.autoDownload)
    }

    public func analyze(_ url: URL, autoStart: Bool = false) {
        guard let service else { return }
        if stage == .downloading { enqueue(url); return }

        job?.cancel()
        service.configure(network: settings.network)
        clipboard.consume(url)
        clipboardSuggestion = nil
        currentURL = url
        urlText = url.absoluteString
        source = MediaSource.detect(url)
        stage = .analyzing
        errorText = nil
        finished = nil
        thumbnail = nil
        coverSavedAt = nil
        options = []
        info = nil
        expandedID = nil
        showAlternatives = false

        job = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await service.fetchInfo(url: url)
                guard !Task.isCancelled else { return }
                let info = resolved.info
                // Скачивать нужно по той ссылке, которая сработала: у Vimeo это
                // может быть страница плеера, а не та, что вставил пользователь.
                self.currentURL = resolved.url
                let built = OptionBuilder.build(from: info, canMerge: self.toolchain.canMerge)
                guard !built.isEmpty else {
                    throw YTVDError.tool("У этой ссылки нет доступных для скачивания форматов")
                }
                self.info = info
                self.options = built
                self.applyDefaultSelection()
                self.stage = .ready
                self.loadThumbnail(info)
                if autoStart { self.download() }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.fail(error)
            }
        }
    }

    private func loadThumbnail(_ info: MediaInfo) {
        guard let raw = info.bestThumbnail?.url, let url = URL(string: raw) else { return }
        Task { [weak self] in
            guard let data = try? await ThumbnailService.fetch(url),
                  let image = ThumbnailService.image(from: data) else { return }
            guard let self, self.info?.id == info.id else { return }
            self.thumbnail = image
            // Площадки часто не сообщают размер лучшей обложки — берём его из самой картинки.
            self.refineCoverOption(image: image, bytes: Int64(data.count))
        }
    }

    private func refineCoverOption(image: NSImage, bytes: Int64) {
        guard let index = options.firstIndex(where: { $0.group == .cover }) else { return }
        let old = options[index]
        guard let rep = image.representations.first else { return }
        let size = "\(rep.pixelsWide)×\(rep.pixelsHigh)"

        options[index] = DownloadOption(
            id: old.id, group: old.group, tint: old.tint, title: old.title,
            subtitle: size, bytes: bytes, estimated: false, badge: old.badge,
            detail: "JPEG · \(size) · сохраняется рядом с видео",
            hint: old.hint, plan: old.plan, height: rep.pixelsHigh)
    }

    // MARK: - скачивание

    public func download() {
        guard let service, let url = currentURL else { return }

        // Может быть выбрана только обложка — тогда качаем её одну.
        guard let option = selectedOption else {
            if coverSelected { saveCoverOnly() }
            return
        }

        job?.cancel()
        service.configure(network: settings.network)
        stage = .downloading
        progress = nil
        phaseText = "подключение…"
        errorText = nil
        finished = nil
        startedAt = Date()

        let plan = option.plan
        let baseName = makeBaseName(for: option)
        let directory = settings.directory
        let alsoCover = coverSelected || settings.saveCoverAlongside
        let coverURL = coverOption?.plan.coverURL

        job = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.download(
                    plan: plan, url: url, directory: directory, baseName: baseName,
                    onEvent: { event in
                        Task { @MainActor [weak self] in self?.apply(event) }
                    })

                if alsoCover, let coverURL, let source = URL(string: coverURL) {
                    let destination = directory.appendingPathComponent(baseName + ".jpg")
                    self.coverSavedAt = try? await ThumbnailService.saveJPEG(from: source, to: destination)
                }

                guard !Task.isCancelled else { return }
                self.complete(result: result, option: option)
            } catch let error as YTVDError where error == .cancelled {
                self.stage = .ready
                self.progress = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.fail(error)
            }
        }
    }

    /// Скачивание одной обложки, без видео.
    private func saveCoverOnly() {
        guard let coverURL = coverOption?.plan.coverURL, let source = URL(string: coverURL) else { return }
        let base = makeBaseName(for: coverOption)
        let destination = settings.directory.appendingPathComponent(base + ".jpg")
        stage = .downloading
        phaseText = "обложка"
        startedAt = Date()

        job = Task { [weak self] in
            guard let self else { return }
            do {
                let file = try await ThumbnailService.saveJPEG(from: source, to: destination)
                let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
                self.coverSavedAt = file
                self.finished = Finished(file: file, bytes: size ?? 0, seconds: self.elapsed())
                self.history.add(HistoryEntry(title: self.info?.displayTitle ?? file.lastPathComponent,
                                              quality: "Обложка JPEG", bytes: size ?? 0,
                                              path: file.path, source: self.source))
                self.stage = .done
            } catch {
                self.fail(error)
            }
        }
    }

    private func apply(_ event: MediaService.Event) {
        switch event {
        case .phase(let text): phaseText = text
        case .progress(let value): progress = value
        }
    }

    private func complete(result: MediaService.DownloadResult, option: DownloadOption) {
        let seconds = elapsed()
        finished = Finished(file: result.file, bytes: result.bytes, seconds: seconds)
        phaseText = "готово"
        stage = .done
        history.add(HistoryEntry(
            title: info?.displayTitle ?? result.file.lastPathComponent,
            quality: "\(option.title) · \(option.plan.container.uppercased())",
            bytes: result.bytes, path: result.file.path, source: source))
        startNextInQueue()
    }

    // MARK: - самолечение движка

    /// Сбой похож на устаревший yt-dlp — только тогда и лезем в сеть за версией.
    private func considerEngineUpdate() {
        guard engineUpdate == nil, !engineUpdating else { return }
        let current = toolchain.ytdlpVersion
        Task { [weak self] in
            guard let update = await EngineUpdater.check(current: current) else { return }
            self?.engineUpdate = update
        }
    }

    public func updateEngine() {
        guard !engineUpdating else { return }
        engineUpdating = true
        engineNote = nil
        Task { [weak self] in
            defer { self?.engineUpdating = false }
            do {
                _ = try await EngineUpdater.installYtDlp()
                await self?.refreshToolchain()
                self?.engineUpdate = nil
                self?.engineNote = "Движок обновлён — попробуйте ещё раз"
            } catch {
                self?.engineNote = (error as? YTVDError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    /// Докачивает недостающий инструмент: ffmpeg для склейки, движок целиком.
    public func installMissingTool() {
        guard !engineUpdating else { return }
        engineUpdating = true
        engineNote = nil
        Task { [weak self] in
            defer { self?.engineUpdating = false }
            do {
                if self?.toolchain.canSolveYouTube == false || self?.toolchain.isReady == false {
                    _ = try await EngineUpdater.installYtDlp()
                }
                if self?.toolchain.canMerge == false {
                    _ = try await EngineUpdater.installFfmpeg()
                }
                await self?.refreshToolchain()
                self?.engineNote = "Готово — попробуйте ещё раз"
            } catch {
                self?.engineNote = (error as? YTVDError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private func fail(_ error: Error) {
        if case YTVDError.engineStale = error { considerEngineUpdate() }
        errorText = (error as? YTVDError)?.errorDescription ?? error.localizedDescription
        progress = nil
        // Если варианты уже разобраны, оставляем их на экране: с ошибкой можно
        // повторить попытку или выбрать другое качество, не начиная заново.
        stage = options.isEmpty ? .failed : .ready
    }

    private func elapsed() -> Int {
        guard let startedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(startedAt)))
    }

    public func cancel() {
        job?.cancel()
        service?.cancel()
        progress = nil
        stage = options.isEmpty ? .idle : .ready
    }

    // MARK: - очередь

    private func enqueue(_ url: URL) {
        guard !queue.contains(where: { $0.url == url }), url != currentURL else { return }
        clipboard.consume(url)
        queue.append(QueueItem(url: url, title: nil, source: MediaSource.detect(url)))
    }

    private func startNextInQueue() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        // Очередь работает автоматически: качество берём из настроек.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self.analyze(next.url, autoStart: true)
        }
    }

    // MARK: - действия с результатом

    public func saveCoverNow() {
        guard let coverURL = coverOption?.plan.coverURL, let source = URL(string: coverURL) else { return }
        let base = makeBaseName(for: selectedOption ?? coverOption)
        let destination = settings.directory.appendingPathComponent(base + ".jpg")
        Task { [weak self] in
            self?.coverSavedAt = try? await ThumbnailService.saveJPEG(from: source, to: destination)
        }
    }

    public func revealInFinder() {
        guard let file = finished?.file ?? coverSavedAt else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    public func openFile() {
        guard let file = finished?.file else { return }
        NSWorkspace.shared.open(file)
    }

    public func openDownloadDirectory() {
        NSWorkspace.shared.open(settings.directory)
    }

    /// Возврат к начальному экрану: снимает всё, включая текущую загрузку и очередь.
    public func reset() {
        job?.cancel()
        service?.cancel()
        stage = .idle
        urlText = ""
        info = nil
        options = []
        selectedID = nil
        coverSelected = false
        expandedID = nil
        showAlternatives = false
        openGroups = [.video, .audio, .cover]
        progress = nil
        phaseText = ""
        errorText = nil
        finished = nil
        thumbnail = nil
        coverSavedAt = nil
        currentURL = nil
        clipboardSuggestion = nil
        queue.removeAll()
        bigPreview = false
        panel = nil
    }

    public func chooseDirectory() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.canCreateDirectories = true
        picker.directoryURL = settings.directory
        picker.prompt = "Выбрать"
        picker.message = "Куда складывать скачанное"
        if picker.runModal() == .OK, let url = picker.url {
            settings.directory = url
        }
    }

    // MARK: - подстановка состояния для тестов и офскрин-снимков

    /// Подстановка вариантов без обращения к сети.
    func setOptionsForTesting(_ options: [DownloadOption],
                              info: MediaInfo? = MediaInfo(id: "test", title: "Ролик", duration: 600)) {
        self.info = info
        self.options = options
        self.stage = .ready
        applyDefaultSelection()
    }

    func setStageForTesting(_ stage: Stage, info: MediaInfo?, options: [DownloadOption]) {
        self.info = info
        self.options = options
        self.stage = stage
    }

    func setSourceForTesting(_ source: MediaSource) { self.source = source }

    func setThumbnailForTesting(_ image: NSImage) { self.thumbnail = image }

    func setClipboardSuggestionForTesting(_ url: URL?) { self.clipboardSuggestion = url }

    func setToolchainForTesting(_ toolchain: Toolchain) { self.toolchain = toolchain }

    func setProgressForTesting(_ progress: DownloadProgress, phase: String) {
        self.progress = progress
        self.phaseText = phase
    }

    func setFinishedForTesting(file: URL, bytes: Int64, seconds: Int) {
        self.finished = Finished(file: file, bytes: bytes, seconds: seconds)
        self.phaseText = "готово"
        self.stage = .done
    }

    /// Проходит через настоящую обработку ошибки, а не подменяет состояние.
    func setErrorForTesting(_ message: String) {
        fail(YTVDError.tool(message))
    }

    // MARK: - имя файла

    func makeBaseName(for option: DownloadOption?) -> String {
        let title = Fmt.safeFileName(info?.displayTitle ?? "video")
        let quality = option.map { option -> String in
            switch option.group {
            case .video: option.title
            case .audio: option.title
            case .cover: "cover"
            }
        } ?? ""
        let base = FileNaming.build(template: settings.fileNameTemplate, title: title,
                                    quality: quality, source: source.title,
                                    id: info?.id ?? "")
        let extensions = ["mp4", "webm", "mkv", "mp3", "m4a", "opus", "jpg"]
        return FileNaming.uniqueBase(directory: settings.directory, base: base, extensions: extensions)
    }
}
