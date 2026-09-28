import AVFoundation
import AVKit
import os
import UIKit

/// Проигрывание скачанного видео системным плеером.
///
/// AVPlayerViewController сам даёт перемотку, полный экран, повороты, AirPlay, скорость
/// и системную громкость. Здесь — то, что он сам не сделает: звук в фоне, «картинка
/// в картинке» после закрытия плеера и название с обложкой на экране блокировки.
@MainActor
final class PlaybackController: NSObject, AVPlayerViewControllerDelegate {

    static let shared = PlaybackController()

    /// Держим плеер, пока идёт «картинка в картинке»: иначе он исчезнет вместе с окном.
    private var current: AVPlayerViewController?
    private var pictureInPicture = false
    private let log = Logger(subsystem: "studio.dk.videodownloader", category: "player")

    func play(_ item: VideoItem) {
        guard item.fileExists else {
            log.error("нет файла \(item.fileName, privacy: .public)")
            return
        }
        activateAudioSession()

        let playerItem = AVPlayerItem(url: item.fileURL)
        playerItem.externalMetadata = Self.metadata(for: item)
        let player = AVPlayer(playerItem: playerItem)

        current?.player?.pause()
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = self
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        controller.modalPresentationStyle = .fullScreen
        current = controller

        Self.topController()?.present(controller, animated: true) { player.play() }
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

    /// Плеер закрыли: если «картинки в картинке» нет — останавливаем звук и отпускаем плеер.
    nonisolated func playerViewController(
        _ controller: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        // UIKit зовёт делегата в главном потоке.
        MainActor.assumeIsolated {
            _ = coordinator.animate(alongsideTransition: nil) { _ in
                if !self.pictureInPicture, controller.presentingViewController == nil {
                    self.release(controller)
                }
            }
        }
    }

    private func release(_ controller: AVPlayerViewController) {
        controller.player?.pause()
        if current === controller { current = nil }
    }

    // MARK: - вспомогательное

    /// Название, канал и обложка — для экрана блокировки и Пункта управления.
    private static func metadata(for item: VideoItem) -> [AVMetadataItem] {
        var list = [metadataItem(.commonIdentifierTitle, value: item.title as NSString)]
        if let channel = item.channel {
            list.append(metadataItem(.commonIdentifierArtist, value: channel as NSString))
        }
        if let url = item.thumbnailURL, let data = try? Data(contentsOf: url) {
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
