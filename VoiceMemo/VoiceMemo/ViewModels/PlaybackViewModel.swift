import Foundation
import AVFoundation
import Observation

@Observable
final class PlaybackViewModel {
    var isPlaying = false
    var currentTime: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play(memo: Memo) {
        do {
            player = try AVAudioPlayer(contentsOf: memo.audioFileURL)
            player?.play()
            isPlaying = true
            startTimer()
        } catch {
            isPlaying = false
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    /// Feed this the audioTimeRange attribute pulled off a transcript run
    /// to decide whether that word should be highlighted right now.
    func isWordHighlighted(range: CMTimeRange) -> Bool {
        let start = range.start.seconds
        let duration = range.duration.seconds
        return currentTime >= start && currentTime < start + duration
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
            if !player.isPlaying {
                self.isPlaying = false
                self.timer?.invalidate()
            }
        }
    }
}
