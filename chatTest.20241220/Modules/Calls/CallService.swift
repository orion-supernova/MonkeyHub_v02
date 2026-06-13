import Foundation
import Combine
import WebRTC
import AVFoundation

/// Owns the WebRTC peer connection for a single 1:1 call: media capture,
/// SDP offer/answer, ICE, and local/remote track plumbing. Signaling is
/// delegated to `CallSignalingManager`; this class is transport-agnostic.
@MainActor
final class CallService: NSObject, ObservableObject {
    static let shared = CallService()

    // Published call state for the UI.
    @Published private(set) var activeCall: Call?
    @Published private(set) var connectionState: RTCIceConnectionState = .new
    @Published var isMicMuted = false
    @Published var isCameraOff = false
    @Published var isSpeakerOn = true
    @Published private(set) var hasRemoteVideo = false

    // Remote/local video tracks exposed for SwiftUI renderers.
    @Published private(set) var localVideoTrack: RTCVideoTrack?
    @Published private(set) var remoteVideoTrack: RTCVideoTrack?

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    }()

    private var peerConnection: RTCPeerConnection?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var localAudioTrack: RTCAudioTrack?
    private var pendingRemoteCandidates: [RTCIceCandidate] = []
    private var hasRemoteDescription = false

    /// Emits locally-generated ICE candidates that signaling must forward to the peer.
    let onLocalCandidate = PassthroughSubject<RTCIceCandidate, Never>()
    /// Emits a locally-created SDP (offer/answer) that signaling must forward.
    let onLocalSDP = PassthroughSubject<RTCSessionDescription, Never>()

    private override init() { super.init() }

    // MARK: - Lifecycle

    func setActiveCall(_ call: Call?) { activeCall = call }

    /// Builds the peer connection with the given ICE servers and attaches local media.
    func start(iceServers: [IceServerConfig], video: Bool) {
        // Voice calls default to the earpiece; video calls to the speaker.
        isSpeakerOn = video
        configureAudioSession(video: video)
        let config = RTCConfiguration()
        config.iceServers = iceServers.map {
            if let user = $0.username, let cred = $0.credential {
                return RTCIceServer(urlStrings: $0.urls, username: user, credential: cred)
            }
            return RTCIceServer(urlStrings: $0.urls)
        }
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self)

        attachLocalMedia(video: video)
    }

    private func attachLocalMedia(video: Bool) {
        guard let pc = peerConnection else { return }

        // Audio
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = Self.factory.audioSource(with: audioConstraints)
        let audioTrack = Self.factory.audioTrack(with: audioSource, trackId: "audio0")
        localAudioTrack = audioTrack
        pc.add(audioTrack, streamIds: ["stream0"])

        // Video (optional)
        guard video else { return }
        let videoSource = Self.factory.videoSource()
        let capturer = RTCCameraVideoCapturer(delegate: videoSource)
        videoCapturer = capturer
        let track = Self.factory.videoTrack(with: videoSource, trackId: "video0")
        localVideoTrack = track
        pc.add(track, streamIds: ["stream0"])
        startCapture(capturer)
    }

    private func startCapture(_ capturer: RTCCameraVideoCapturer) {
        guard let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front })
            ?? RTCCameraVideoCapturer.captureDevices().first else { return }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let format = formats.sorted { a, b in
            let wa = CMVideoFormatDescriptionGetDimensions(a.formatDescription).width
            let wb = CMVideoFormatDescriptionGetDimensions(b.formatDescription).width
            return wa < wb
        }.first { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width >= 640 } ?? formats.last
        guard let format else { return }
        let fps = (format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 30)
        capturer.startCapture(with: device, format: format, fps: Int(min(fps, 30)))
    }

    // MARK: - Offer / Answer

    func createOffer() async -> RTCSessionDescription? {
        guard let pc = peerConnection else { return nil }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let sdp = try? await pc.offer(for: constraints) else { return nil }
        try? await pc.setLocalDescription(sdp)
        onLocalSDP.send(sdp)
        return sdp
    }

    func createAnswer() async -> RTCSessionDescription? {
        guard let pc = peerConnection else { return nil }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let sdp = try? await pc.answer(for: constraints) else { return nil }
        try? await pc.setLocalDescription(sdp)
        onLocalSDP.send(sdp)
        return sdp
    }

    func setRemoteDescription(_ sdp: RTCSessionDescription) async {
        guard let pc = peerConnection else { return }
        try? await pc.setRemoteDescription(sdp)
        hasRemoteDescription = true
        for c in pendingRemoteCandidates { pc.add(c) { _ in } }
        pendingRemoteCandidates.removeAll()
    }

    func addRemoteCandidate(_ candidate: RTCIceCandidate) {
        guard let pc = peerConnection else { return }
        if hasRemoteDescription {
            pc.add(candidate) { _ in }
        } else {
            pendingRemoteCandidates.append(candidate)
        }
    }

    // MARK: - Controls

    func toggleMic() {
        isMicMuted.toggle()
        localAudioTrack?.isEnabled = !isMicMuted
    }

    func toggleCamera() {
        isCameraOff.toggle()
        localVideoTrack?.isEnabled = !isCameraOff
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
        #endif
    }

    // MARK: - Teardown

    func tearDown() {
        videoCapturer?.stopCapture()
        videoCapturer = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        localAudioTrack = nil
        peerConnection?.close()
        peerConnection = nil
        hasRemoteDescription = false
        pendingRemoteCandidates.removeAll()
        connectionState = .new
        hasRemoteVideo = false
        isMicMuted = false
        isCameraOff = false
        deactivateAudioSession()
    }

    // MARK: - Audio session

    private func configureAudioSession(video: Bool) {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // Only video calls default the route to the speaker; voice calls use the
        // earpiece unless the user toggles the speaker.
        var options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP]
        if video { options.insert(.defaultToSpeaker) }
        try? session.setCategory(.playAndRecord, mode: video ? .videoChat : .voiceChat, options: options)
        try? session.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

// MARK: - RTCPeerConnectionDelegate

extension CallService: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor in self.onLocalCandidate.send(candidate) }
    }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in self.connectionState = newState }
    }

    nonisolated func peerConnection(_ pc: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCVideoTrack {
            Task { @MainActor in
                self.remoteVideoTrack = track
                self.hasRemoteVideo = true
            }
        }
    }

    // Unused delegate requirements.
    nonisolated func peerConnectionShouldNegotiate(_ pc: RTCPeerConnection) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
