import Foundation
import AVFoundation

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    func play(url: URL) {
        do {
            if audioPlayer == nil {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.delegate = self
                duration = audioPlayer?.duration ?? 0
            }
            audioPlayer?.play()
            isPlaying = true
            isPaused = false
            startTimer()
        } catch {
            print("Failed to play audio: \(error)")
        }
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        isPaused = true
        stopTimer()
    }

    func resume() {
        audioPlayer?.play()
        isPlaying = true
        isPaused = false
        startTimer()
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        isPaused = false
        stopTimer()
        audioPlayer = nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.currentTime = self?.audioPlayer?.currentTime ?? 0
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
