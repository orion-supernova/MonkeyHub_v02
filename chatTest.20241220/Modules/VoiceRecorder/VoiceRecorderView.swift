import SwiftUI
import AVFoundation

struct VoiceRecorderView: View {
    @Binding var isPresented: Bool
    var onAudioRecorded: (URL) -> Void

    @State private var audioRecorder: AVAudioRecorder?
    @State private var recording = false
    @State private var recordedAudioURL: URL?
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 30) // For waveform

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: selectedTheme.colors(for: colorScheme).headerBackground,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: {
                        isPresented = false
                        stopRecording(cancel: true)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                VStack(spacing: 20) {
                    if recordedAudioURL == nil {
                        Text(recording ? "Recording..." : "Tap to Record")
                            .font(.title.bold())
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    } else {
                        Text("Review Recording")
                            .font(.title.bold())
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    }

                    Text(timeString(from: recordingTime))
                        .font(.largeTitle.monospacedDigit())
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                    WaveformView(audioLevels: audioLevels, isRecording: recording)
                        .frame(height: 80)
                        .padding(.horizontal)

                    if recordedAudioURL == nil {
                        Button(action: {
                            if recording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: recording
                                                ? [Color.red, Color.red.opacity(0.7)]
                                                : selectedTheme.colors(for: colorScheme).primary,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .shadow(
                                        color: recording
                                            ? Color.red.opacity(0.4)
                                            : selectedTheme.colors(for: colorScheme).primary[0]
                                                .opacity(0.4),
                                        radius: 10,
                                        y: 5
                                    )

                                Image(systemName: recording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                            }
                        }
                    } else {
                        HStack(spacing: 30) {
                            Button(action: {
                                recordedAudioURL = nil
                                recordingTime = 0
                                startRecording()
                            }) {
                                VStack {
                                    ZStack {
                                        Circle()
                                            .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                                            .frame(width: 60, height: 60)
                                            .shadow(
                                                color: selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.2),
                                                radius: 5, y: 2
                                            )
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 30))
                                            .foregroundStyle(selectedTheme.colors(for: colorScheme).destructive)
                                    }
                                    Text("Retake")
                                        .font(.caption)
                                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                                }
                            }

                            Button(action: {
                                if let url = recordedAudioURL {
                                    onAudioRecorded(url)
                                }
                                isPresented = false
                            }) {
                                VStack {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: selectedTheme.colors(for: colorScheme).primary,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 60, height: 60)
                                            .shadow(
                                                color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.4),
                                                radius: 5, y: 2
                                            )
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 30))
                                            .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                                    }
                                    Text("Send")
                                        .font(.caption)
                                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
        }
        .onDisappear {
            if recording {
                stopRecording(cancel: true)
            }
        }
    }

    private func startRecording() {
        let recordingSession = AVAudioSession.sharedInstance()
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
            let audioFilename = getDocumentsDirectory().appendingPathComponent("\(UUID().uuidString).m4a")
            recordedAudioURL = nil
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100, // Increased sample rate for better quality
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.isMeteringEnabled = true // Enable metering
            audioRecorder?.record()
            recording = true
            recordingTime = 0
            startTimer()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func stopRecording(cancel: Bool = false) {
        let finalRecordedURL = audioRecorder?.url // Capture the URL before nil-ing out audioRecorder
        audioRecorder?.stop()
        audioRecorder = nil
        recording = false
        stopTimer()
        if !cancel, let url = finalRecordedURL { // Use the captured URL
            self.recordedAudioURL = url
        } else if cancel { // If cancelled, ensure recordedAudioURL is nil
            self.recordedAudioURL = nil
        }
        audioLevels = Array(repeating: 0.1, count: 30) // Reset waveform
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    private func startTimer() {
        timer?.invalidate() // Invalidate existing timer if any
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in // Update more frequently
            recordingTime += 0.1
            if let recorder = audioRecorder, recorder.isRecording {
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0) // Get average power
                let normalizedPower = max(0, min(1, (power + 50) / 50)) // Normalize to 0-1
                audioLevels.append(CGFloat(normalizedPower))
                if audioLevels.count > 30 { // Keep a fixed number of bars
                    audioLevels.removeFirst()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func timeString(from time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct WaveformView: View {
    let audioLevels: [CGFloat]
    let isRecording: Bool
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(audioLevels.indices, id: \.self) {
                index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(selectedTheme.colors(for: colorScheme).accent)
                    .frame(width: 4, height: max(5, audioLevels[index] * 70)) // Ensure minimum height
                    .animation(.easeOut(duration: 0.1), value: audioLevels[index])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selectedTheme.colors(for: colorScheme).cardBackground.opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selectedTheme.colors(for: colorScheme).accent.opacity(0.3), lineWidth: 1)
        )
    }
}
