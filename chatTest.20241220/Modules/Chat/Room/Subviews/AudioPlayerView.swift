import SwiftUI
import AVFoundation

struct AudioPlayerView: View {
    let url: URL
    @StateObject private var audioPlayerManager = AudioPlayerManager()
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                if audioPlayerManager.isPlaying {
                    audioPlayerManager.pause()
                } else {
                    if audioPlayerManager.isPaused {
                        audioPlayerManager.resume()
                    } else {
                        audioPlayerManager.play(url: url)
                    }
                }
            }) {
                Image(systemName: audioPlayerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundColor(selectedTheme.colors(for: colorScheme).text)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: selectedTheme.colors(for: colorScheme).primary,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Slider(value: $audioPlayerManager.currentTime, in: 0...audioPlayerManager.duration) {
                    Text("Time")
                } onEditingChanged: { isEditing in
                    if !isEditing {
                        audioPlayerManager.seek(to: audioPlayerManager.currentTime)
                    }
                }
                .tint(selectedTheme.colors(for: colorScheme).accent)

                HStack {
                    Text(timeString(from: audioPlayerManager.currentTime))
                    Spacer()
                    Text(timeString(from: audioPlayerManager.duration))
                }
                .font(.caption)
                .foregroundColor(selectedTheme.colors(for: colorScheme).textSecondary)
            }
        }
        .padding()
        .background(selectedTheme.colors(for: colorScheme).cardBackground)
        .cornerRadius(16)
    }

    private func timeString(from time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
