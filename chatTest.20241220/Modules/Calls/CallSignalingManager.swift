import Foundation
import Combine
import ConvexMobile
import WebRTC

/// Bridges Convex `callSignals` to the local `CallService`: subscribes to
/// inbound signals for the current user, applies offers/answers/ICE/bye, and
/// forwards locally-generated SDP/ICE back out via `ConvexCallsAPI`.
@MainActor
final class CallSignalingManager: ObservableObject {
    static let shared = CallSignalingManager()

    private let api = ConvexCallsAPI.shared
    private let callService = CallService.shared
    private let client = ConvexService.shared.client

    private var signalSubscription: AnyCancellable?
    private var localCandidateSink: AnyCancellable?
    private var localSDPSink: AnyCancellable?

    private var userId: String = ""
    /// The call this manager is currently wired to.
    private(set) var callId: String?
    private var peerUserId: String?
    /// Whether we are the caller (created the offer) for the active call.
    private var isCaller = false
    /// Media signals (offer/answer/ice) that arrived before we were bound to
    /// their call — replayed once `bind()` sets up the peer connection. Without
    /// this, an offer that lands before the callee accepts would be lost, since
    /// the Convex subscription won't re-emit unchanged rows.
    private var bufferedMediaSignals: [String: [CallSignal]] = [:]
    /// Signal ids already applied, to avoid double-applying buffered + live.
    private var appliedSignalIds = Set<String>()

    private init() {}

    // MARK: - Wiring

    /// Begins listening for inbound signals for `userId`. Call once after login.
    func startListening(userId: String) {
        self.userId = userId
        signalSubscription?.cancel()
        signalSubscription = client
            .subscribe(to: "calls:signalsForUser", with: ["userId": userId], yielding: [ConvexCallSignalDoc].self)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        AppLogger.shared.logError("calls:signalsForUser subscription", error)
                    }
                },
                receiveValue: { [weak self] docs in
                    Task { await self?.handleSignals(docs.map { $0.toCallSignal() }) }
                }
            )
    }

    func stopListening() {
        signalSubscription?.cancel()
        signalSubscription = nil
        bufferedMediaSignals.removeAll()
        appliedSignalIds.removeAll()
    }

    /// Binds the manager to a specific call and starts forwarding local media
    /// negotiation outputs (SDP + ICE) to the peer.
    func bind(callId: String, peerUserId: String, isCaller: Bool) {
        self.callId = callId
        self.peerUserId = peerUserId
        self.isCaller = isCaller

        localCandidateSink = callService.onLocalCandidate
            .sink { [weak self] candidate in
                Task { await self?.sendCandidate(candidate) }
            }
        localSDPSink = callService.onLocalSDP
            .sink { [weak self] sdp in
                Task { await self?.sendSDP(sdp) }
            }

        // Replay any media signals (e.g. the caller's offer) that arrived for
        // this call before we were bound and set up the peer connection.
        if let pending = bufferedMediaSignals.removeValue(forKey: callId), !pending.isEmpty {
            Task {
                for signal in pending where !appliedSignalIds.contains(signal.id) {
                    appliedSignalIds.insert(signal.id)
                    await apply(signal)
                    try? await api.consumeSignal(signalId: signal.id, userId: userId)
                }
            }
        }
    }

    func unbind() {
        localCandidateSink?.cancel(); localCandidateSink = nil
        localSDPSink?.cancel(); localSDPSink = nil
        if let callId { bufferedMediaSignals[callId] = nil }
        callId = nil; peerUserId = nil
        appliedSignalIds.removeAll()
    }

    // MARK: - Outbound

    private func sendSDP(_ sdp: RTCSessionDescription) async {
        guard let callId, let peerUserId else { return }
        let kind: CallSignalKind = sdp.type == .offer ? .offer : .answer
        let payload = ["sdp": sdp.sdp, "type": Self.string(for: sdp.type)]
        guard let json = Self.jsonString(payload) else { return }
        try? await api.sendSignal(callId: callId, fromUserId: userId, toUserId: peerUserId,
                                  kind: kind, payload: json, fromDeviceId: DeviceIdentityManager.deviceId)
    }

    private func sendCandidate(_ candidate: RTCIceCandidate) async {
        guard let callId, let peerUserId else { return }
        let payload: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "sdpMid": candidate.sdpMid ?? ""
        ]
        guard let json = Self.jsonString(payload) else { return }
        try? await api.sendSignal(callId: callId, fromUserId: userId, toUserId: peerUserId,
                                  kind: .ice, payload: json, fromDeviceId: DeviceIdentityManager.deviceId)
    }

    // MARK: - Inbound

    private func handleSignals(_ signals: [CallSignal]) async {
        for signal in signals {
            switch signal.kind {
            case .offer, .answer, .ice, .handoffOffer, .handoffAnswer:
                if let callId, signal.callId == callId {
                    // Bound to this call — apply now.
                    guard !appliedSignalIds.contains(signal.id) else {
                        try? await api.consumeSignal(signalId: signal.id, userId: userId)
                        continue
                    }
                    appliedSignalIds.insert(signal.id)
                    await apply(signal)
                    try? await api.consumeSignal(signalId: signal.id, userId: userId)
                } else {
                    // Not yet bound to this call (e.g. callee hasn't accepted).
                    // Buffer locally and DON'T consume, so it survives until
                    // bind() replays it against a ready peer connection.
                    var pending = bufferedMediaSignals[signal.callId] ?? []
                    if !pending.contains(where: { $0.id == signal.id }) {
                        pending.append(signal)
                        bufferedMediaSignals[signal.callId] = pending
                    }
                }
            case .bye, .reject, .cancel:
                await apply(signal)
                try? await api.consumeSignal(signalId: signal.id, userId: userId)
            default:
                // invite/state/taken/handoff-* — consume; call presence is
                // driven by the activeCallForUser subscription in CallController.
                try? await api.consumeSignal(signalId: signal.id, userId: userId)
            }
        }
    }

    private func apply(_ signal: CallSignal) async {
        switch signal.kind {
        case .offer, .handoffOffer:
            guard let sdp = Self.sdp(from: signal.payload) else { return }
            await callService.setRemoteDescription(sdp)
            _ = await callService.createAnswer()
        case .answer, .handoffAnswer:
            guard let sdp = Self.sdp(from: signal.payload) else { return }
            await callService.setRemoteDescription(sdp)
        case .ice:
            if let candidate = Self.candidate(from: signal.payload) {
                callService.addRemoteCandidate(candidate)
            }
        case .bye, .reject, .cancel:
            NotificationCenter.default.post(name: .callEndedRemotely, object: nil,
                                            userInfo: ["callId": signal.callId])
        default:
            break
        }
    }

    // MARK: - JSON helpers

    private static func jsonString(_ dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func dict(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func sdp(from json: String) -> RTCSessionDescription? {
        guard let d = dict(from: json), let sdp = d["sdp"] as? String,
              let typeStr = d["type"] as? String else { return nil }
        return RTCSessionDescription(type: sdpType(from: typeStr), sdp: sdp)
    }

    private static func candidate(from json: String) -> RTCIceCandidate? {
        guard let d = dict(from: json), let sdp = d["candidate"] as? String else { return nil }
        let mLineIndex = (d["sdpMLineIndex"] as? Int).map(Int32.init) ?? 0
        let mid = d["sdpMid"] as? String
        return RTCIceCandidate(sdp: sdp, sdpMLineIndex: mLineIndex, sdpMid: (mid?.isEmpty == true) ? nil : mid)
    }

    private static func string(for type: RTCSdpType) -> String {
        switch type {
        case .offer: return "offer"
        case .answer: return "answer"
        case .prAnswer: return "pranswer"
        case .rollback: return "rollback"
        @unknown default: return "offer"
        }
    }

    private static func sdpType(from s: String) -> RTCSdpType {
        switch s {
        case "answer": return .answer
        case "pranswer": return .prAnswer
        case "rollback": return .rollback
        default: return .offer
        }
    }
}

extension Notification.Name {
    static let callEndedRemotely = Notification.Name("CallEndedRemotely")
    static let incomingCallReceived = Notification.Name("IncomingCallReceived")
}
