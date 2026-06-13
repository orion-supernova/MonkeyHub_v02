import SwiftUI
import WebRTC

// MARK: - Video renderer

#if os(iOS)
/// Renders an `RTCVideoTrack` via Metal. Re-attaches when the track changes.
struct RTCVideoTrackView: UIViewRepresentable {
    let track: RTCVideoTrack?
    var mirror: Bool = false

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        view.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        track?.add(view)
        context.coordinator.track = track
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        if context.coordinator.track !== track {
            context.coordinator.track?.remove(uiView)
            track?.add(uiView)
            context.coordinator.track = track
        }
        uiView.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { weak var track: RTCVideoTrack? }
}
#else
struct RTCVideoTrackView: View {
    let track: RTCVideoTrack?
    var mirror: Bool = false
    var body: some View { Color.black }
}
#endif

// MARK: - Active call

struct ActiveCallView: View {
    @ObservedObject var controller = CallController.shared
    @ObservedObject var service = CallService.shared

    private var isVideo: Bool { controller.currentCall?.type == .video }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Remote video (or avatar for audio calls).
            if isVideo, service.hasRemoteVideo {
                RTCVideoTrackView(track: service.remoteVideoTrack)
                    .ignoresSafeArea()
            } else {
                audioBackdrop
            }

            // Local self-view PiP.
            if isVideo, let local = service.localVideoTrack, !service.isCameraOff {
                VStack {
                    HStack {
                        Spacer()
                        RTCVideoTrackView(track: local, mirror: true)
                            .frame(width: 110, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2)))
                            .padding()
                    }
                    Spacer()
                }
            }

            VStack {
                header
                Spacer()
                controls
            }
            .padding()
        }
    }

    private var audioBackdrop: some View {
        VStack(spacing: 20) {
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 120, height: 120)
                .overlay(Text(controller.peerName.prefix(1).uppercased()).font(.system(size: 48, weight: .bold)).foregroundStyle(.white))
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(controller.peerName)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 40)
    }

    private var statusText: String {
        switch controller.phase {
        case .outgoing: return "Calling…"
        case .active: return service.connectionState == .connected ? "Connected" : "Connecting…"
        default: return ""
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            CallControlButton(icon: service.isMicMuted ? "mic.slash.fill" : "mic.fill",
                              active: service.isMicMuted) { service.toggleMic() }
            if isVideo {
                CallControlButton(icon: service.isCameraOff ? "video.slash.fill" : "video.fill",
                                  active: service.isCameraOff) { service.toggleCamera() }
            }
            CallControlButton(icon: service.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.fill",
                              active: false) { service.toggleSpeaker() }
            CallControlButton(icon: "phone.down.fill", active: true, tint: .red) {
                Task { await controller.end() }
            }
        }
        .padding(.bottom, 30)
    }
}

private struct CallControlButton: View {
    let icon: String
    let active: Bool
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(tint == .red ? .white : (active ? .black : .white))
                .frame(width: 60, height: 60)
                .background(Circle().fill(tint == .red ? Color.red : (active ? Color.white : Color.white.opacity(0.2))))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Incoming (in-app fallback; CallKit shows native when backgrounded)

struct IncomingCallView: View {
    @ObservedObject var controller = CallController.shared

    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue.opacity(0.4), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .overlay(Text(controller.peerName.prefix(1).uppercased()).font(.system(size: 48, weight: .bold)).foregroundStyle(.white))
                Text(controller.peerName).font(.title.bold()).foregroundStyle(.white)
                Text(controller.currentCall?.type == .video ? "Incoming video call…" : "Incoming call…")
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack(spacing: 60) {
                    VStack(spacing: 8) {
                        Button { Task { await controller.reject() } } label: {
                            Image(systemName: "phone.down.fill").font(.system(size: 28)).foregroundStyle(.white)
                                .frame(width: 70, height: 70).background(Circle().fill(.red))
                        }.buttonStyle(.plain)
                        Text("Decline").font(.caption).foregroundStyle(.white)
                    }
                    VStack(spacing: 8) {
                        Button { Task { await controller.accept() } } label: {
                            Image(systemName: "phone.fill").font(.system(size: 28)).foregroundStyle(.white)
                                .frame(width: 70, height: 70).background(Circle().fill(.green))
                        }.buttonStyle(.plain)
                        Text("Accept").font(.caption).foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Overlay host

/// Pill shown when a call is live on another of the user's devices.
struct ActiveCallPill: View {
    @ObservedObject var controller = CallController.shared

    var body: some View {
        Button {
            Task { await controller.handoffHere() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Call on \(controller.handoffDeviceLabel)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Tap to move it here").font(.system(size: 11)).opacity(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "phone.arrow.down.left.fill").font(.system(size: 14))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing)))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

/// Place once near the app root; presents the call UI based on `phase`.
struct CallOverlayHost: View {
    @ObservedObject var controller = CallController.shared

    var body: some View {
        ZStack {
            switch controller.phase {
            case .incoming:
                IncomingCallView().transition(.move(edge: .bottom))
            case .outgoing, .active:
                ActiveCallView().transition(.move(edge: .bottom))
            case .idle:
                if controller.canHandoff {
                    VStack {
                        ActiveCallPill().transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .padding(.top, 8)
                } else {
                    EmptyView()
                }
            }
        }
        .animation(.spring(response: 0.4), value: phaseKey)
        .animation(.spring(response: 0.4), value: controller.canHandoff)
    }

    private var phaseKey: Int {
        switch controller.phase {
        case .idle: return 0
        case .incoming: return 1
        case .outgoing: return 2
        case .active: return 3
        }
    }
}
