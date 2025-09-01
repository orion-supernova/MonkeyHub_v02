import SwiftUI
import AVFoundation

struct VoiceRecorderView: View {
    @Binding var isPresented: Bool
    var onAudioRecorded: (URL) -> Void

    @State private var audioRecorder: AVAudioRecorder?
    @State private var recording = false
    @State private var recordingURL: URL?

    var body: some View {
        VStack {
            Spacer()
            Text(recording ? "Recording..." : "Tap to Record")
                .font(.title)
            Spacer()
            Button(action: {
                if recording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                Image(systemName: recording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(recording ? .red : .blue)
            }
            Spacer()
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
            recordingURL = audioFilename
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            recording = true
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func stopRecording(cancel: Bool = false) {
        audioRecorder?.stop()
        audioRecorder = nil
        recording = false
        if !cancel, let url = recordingURL {
            onAudioRecorded(url)
        }
        isPresented = false
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}
