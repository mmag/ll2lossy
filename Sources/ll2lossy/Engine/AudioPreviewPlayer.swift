import Foundation
import AVFoundation

@MainActor
final class AudioPreviewPlayer: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var isPlaying = false

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(url: URL) {
        if currentURL == url {
            isPlaying ? pause() : resume()
        } else {
            play(url: url)
        }
    }

    func toggleCurrent() {
        guard currentURL != nil else { return }
        isPlaying ? pause() : resume()
    }

    func isPlaying(url: URL) -> Bool {
        currentURL == url && isPlaying
    }

    func play(url: URL) {
        removeEndObserver()

        let player = AVPlayer(url: url)
        self.player = player
        currentURL = url
        isPlaying = true

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finishPlayback()
            }
        }

        player.play()
    }

    private func resume() {
        player?.play()
        isPlaying = true
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

    private func finishPlayback() {
        player?.seek(to: .zero)
        isPlaying = false
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
