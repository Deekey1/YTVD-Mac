import AVFoundation
import AVKit
import MediaPlayer
import os
import UIKit

/// Проигрывание скачанного видео системным плеером.
///
/// AVPlayerViewController сам даёт перемотку, полный экран, повороты, AirPlay, скорость
/// и системную громкость. Здесь — то, что он сам не сделает: звук в фоне, «картинка
/// в картинке» после закрытия плеера, название с обложкой на экране блокировки,
/// продолжение с того места, где остановились, и плейлист подряд.
@MainActor
final class PlaybackController: NSObject, AVPlayerViewControllerDelegate {

    static let shared = PlaybackController()

    /// Как часто запоминать место во время просмотра: при внезапном выключении
    /// теряется не больше этого. Чаще — лишняя запись на накопитель.
    static let saveInterval: Double = 5

    /// Что играем: одно видео или плейлист. Храним сведения, а не сами записи SwiftData.
    struct Entry: Equatable {
        let id: UUID
        let url: URL
        let title: String
        let channel: String?
        let thumbnailURL: URL?
        let duration: Double?

        init(_ item: VideoItem) {
            id = item.id; url = item.fileURL; title = item.title; channel = item.channel
            thumbnailURL = item.thumbnailURL; duration = item.duration
        }
    }

    /// Держим плеер, пока идёт «картинка в картинке»: иначе он исчезнет вместе с окном.
    private var current: AVPlayerViewController?
    private var pictureInPicture = false
    private var queue: [Entry] = []
    private var index = 0
    /// Пока плеер не перешёл к сохранённому месту, текущее время — ещё 0:00: его не пишем.
    private var positionReady = false
    private var timeObserver: Any?
    private weak var observedPlayer: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private let positions: PlaybackPositions
    private let log = Logger(subsystem: "studio.dk.videodownloader", category: "player")

    init(positions: PlaybackPositions = .shared) {
        self.positions = positions
        super.init()
        let center = NotificationCenter.default
        // Уход в фон, звонок, закрытие приложения — запомнить место и дописать его на диск.
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                     UIApplication.willTerminateNotification] {
            center.addObserver(self, selector: #selector(applicationWillLeave), name: name, object: nil)
        }
        configureRemoteCommands()
    }

    // MARK: - запуск

    /// Одно видео — с того места, где остановились, или сначала.
    func play(_ item: VideoItem, fromStart: Bool = false) {
        play([item], startingWith: item.id, fromStart: fromStart)
    }

    /// Плейлист подряд, начиная с выбранного видео.
    func play(_ items: [VideoItem], startingWith first: UUID? = nil, fromStart: Bool = false) {
        let entries = items.filter(\.fileExists).map(Entry.init)
        guard !entries.isEmpty else {
            log.error("нечего играть: файлов нет")
            return
        }
        // Если что-то уже играет — сначала запомнить его место.
        saveCurrentPosition()
        activateAudioSession()

        queue = entries
        index = first.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        if fromStart { positions.clear(queue[index].id) }

        let player = AVPlayer(playerItem: makeItem(queue[index]))
        current?.player?.pause()
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = self
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        controller.modalPresentationStyle = .fullScreen
        current = controller
        observe(player)
        updateQueueControls()

        let resume = positions.resumeTime(for: queue[index].id)
        Self.topController()?.present(controller, animated: true) { [weak self] in
            self?.start(player, at: resume)
        }
    }

    /// Переход к сохранённому месту и только потом — воспроизведение.
    private func start(_ player: AVPlayer, at seconds: Double?) {
        positionReady = false
        guard let seconds else {
            positionReady = true
            player.play()
            return
        }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.positionReady = true
                player.play()
            }
        }
    }

    private func makeItem(_ entry: Entry) -> AVPlayerItem {
        let item = AVPlayerItem(url: entry.url)
        item.externalMetadata = Self.metadata(for: entry)
        return item
    }

    private func activateAudioSession() {
        do {
            // .playback: звук не глушится переключателем «Без звука» и продолжается в фоне.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log.error("аудиосессия: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - место просмотра

    private func observe(_ player: AVPlayer) {
        stopObserving()
        observedPlayer = player
        // Вызывается и каждые 5 секунд, и при перемотке, паузе и старте.
        let interval = CMTime(seconds: Self.saveInterval, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveCurrentPosition() }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard player.timeControlStatus == .paused else { return }
            Task { @MainActor in self?.saveCurrentPosition() }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let finished = notification.object as? AVPlayerItem
            MainActor.assumeIsolated { self?.itemDidEnd(finished) }
        }
    }

    private func stopObserving() {
        if let timeObserver, let observedPlayer { observedPlayer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observedPlayer = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func saveCurrentPosition() {
        guard positionReady, queue.indices.contains(index),
              let item = current?.player?.currentItem else { return }
        let seconds = item.currentTime().seconds
        let duration = item.duration.seconds
        positions.record(seconds, duration: duration.isFinite ? duration : queue[index].duration,
                         for: queue[index].id)
    }

    @objc nonisolated private func applicationWillLeave() {
        MainActor.assumeIsolated {
            saveCurrentPosition()
            positions.flush()
        }
    }

    // MARK: - плейлист

    private func itemDidEnd(_ item: AVPlayerItem?) {
        guard let player = current?.player, item === player.currentItem, queue.indices.contains(index) else { return }
        positions.clear(queue[index].id)          // досмотрено — в следующий раз сначала
        if index + 1 < queue.count { advance(to: index + 1) }
    }

    private func advance(to newIndex: Int) {
        guard let player = current?.player, queue.indices.contains(newIndex), newIndex != index else { return }
        saveCurrentPosition()
        index = newIndex
        positionReady = false
        player.replaceCurrentItem(with: makeItem(queue[index]))
        updateQueueControls()
        start(player, at: positions.resumeTime(for: queue[index].id))
    }

    /// Переключение видео плейлиста на экране блокировки и в Пункте управления.
    /// Своих кнопок системный плеер на iPhone не принимает — следующее видео включается само.
    private func updateQueueControls() {
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = index + 1 < queue.count
        commands.previousTrackCommand.isEnabled = index > 0
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = false
        commands.previousTrackCommand.isEnabled = false
        commands.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.index + 1 < self.queue.count else { return .noActionableNowPlayingItem }
                self.advance(to: self.index + 1)
                return .success
            }
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.index > 0 else { return .noActionableNowPlayingItem }
                self.advance(to: self.index - 1)
                return .success
            }
        }
    }

    // MARK: - AVPlayerViewControllerDelegate

    nonisolated func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) {
        Task { @MainActor in self.pictureInPicture = true }
    }

    nonisolated func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) {
        Task { @MainActor in
            self.pictureInPicture = false
            if controller.presentingViewController == nil { self.release(controller) }
        }
    }

    /// Пользователь вернулся из «картинки в картинке» — показываем плеер снова.
    nonisolated func playerViewController(
        _ controller: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            guard controller.presentingViewController == nil, let top = Self.topController() else {
                completionHandler(true)
                return
            }
            top.present(controller, animated: true) { completionHandler(true) }
        }
    }

    /// Плеер закрыли: если «картинки в картинке» нет — запоминаем место, останавливаем звук
    /// и отпускаем плеер.
    nonisolated func playerViewController(
        _ controller: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        // UIKit зовёт делегата в главном потоке.
        MainActor.assumeIsolated {
            saveCurrentPosition()
            _ = coordinator.animate(alongsideTransition: nil) { _ in
                if !self.pictureInPicture, controller.presentingViewController == nil {
                    self.release(controller)
                }
            }
        }
    }

    private func release(_ controller: AVPlayerViewController) {
        guard current === controller else {
            controller.player?.pause()
            return
        }
        saveCurrentPosition()
        controller.player?.pause()
        stopObserving()
        current = nil
        queue = []
        index = 0
        positionReady = false
        updateQueueControls()
    }

    // MARK: - вспомогательное

    /// Название, канал и обложка — для экрана блокировки и Пункта управления.
    private static func metadata(for entry: Entry) -> [AVMetadataItem] {
        var list = [metadataItem(.commonIdentifierTitle, value: entry.title as NSString)]
        if let channel = entry.channel {
            list.append(metadataItem(.commonIdentifierArtist, value: channel as NSString))
        }
        if let url = entry.thumbnailURL, let data = try? Data(contentsOf: url) {
            list.append(metadataItem(.commonIdentifierArtwork, value: data as NSData))
        }
        return list
    }

    private static func metadataItem(_ identifier: AVMetadataIdentifier,
                                     value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }

    static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
