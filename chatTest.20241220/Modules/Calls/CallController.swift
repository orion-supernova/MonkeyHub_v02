import Foundation
import Combine
import ConvexMobile

enum CallPhase {
    case idle
    case outgoing   // we're calling, awaiting accept
    case incoming   // someone is calling us
    case active     // connected
}

/// Top-level call orchestrator. Observes call presence via Convex, drives the
/// WebRTC `CallService`, routes signaling, and presents native CallKit UI.
/// The app shows `ActiveCallView`/`IncomingCallView` based on `phase`.
@MainActor
final class CallController: ObservableObject {
    static let shared = CallController()

    @Published private(set) var phase: CallPhase = .idle
    @Published private(set) var currentCall: Call?
    @Published var peerName: String = ""

    private let api = ConvexCallsAPI.shared
    private let callService = CallService.shared
    private let signaling = CallSignalingManager.shared
    private let client = ConvexService.shared.client

    private var userId: String = ""
    private var activeCallSub: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Session

    /// Wires up signaling, presence subscription, and push registration. Call after login.
    func startSession(userId: String) {
        guard self.userId != userId else { return }
        self.userId = userId
        signaling.startListening(userId: userId)

        activeCallSub = client
            .subscribe(to: "calls:activeCallForUser", with: ["userId": userId], yielding: ConvexActiveCallDoc?.self)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] doc in
                self?.handlePresence(doc?.toCall())
            })

        NotificationCenter.default.publisher(for: .callEndedRemotely)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.teardown() }
            .store(in: &cancellables)

        #if os(iOS)
        PushKitManager.shared.register(userId: userId)
        CallKitManager.shared.onAnswer = { [weak self] _ in Task { await self?.accept() } }
        CallKitManager.shared.onEnd = { [weak self] _ in
            Task {
                // Declining a still-ringing incoming call must `reject` (so the
                // caller + sibling devices get the rejection), not `end`.
                guard let self else { return }
                if self.phase == .incoming { await self.reject() } else { await self.end() }
            }
        }
        CallKitManager.shared.onMute = { [weak self] _, muted in
            if self?.callService.isMicMuted != muted { self?.callService.toggleMic() }
        }
        #else
        Task { try? await api.registerDevice(userId: userId) }
        #endif
    }

    func endSession() {
        activeCallSub?.cancel(); activeCallSub = nil
        signaling.stopListening()
        teardown()
        userId = ""
    }

    // MARK: - Presence-driven state

    private func handlePresence(_ call: Call?) {
        guard let call else {
            // No live call anywhere: tear down if we're in one, otherwise clear
            // stale state so the "Move call here" pill can't linger.
            if phase != .idle { teardown() } else if currentCall != nil { currentCall = nil }
            return
        }
        // activeCallForUser returns only ONE call and may flip to a different
        // (e.g. a new incoming) one. Don't let it clobber the call we're on.
        if phase != .idle, let cur = currentCall, cur.id != call.id { return }

        currentCall = call
        peerName = call.peerName ?? "Unknown"

        switch call.status {
        case .ringing:
            if call.callerId != userId, phase == .idle {
                phase = .incoming
                #if os(iOS)
                CallKitManager.shared.reportIncoming(callId: call.id, callerName: peerName,
                                                     hasVideo: call.type == .video)
                #endif
            }
        case .active:
            if phase == .outgoing || phase == .incoming {
                let wasOutgoing = phase == .outgoing
                phase = .active
                #if os(iOS)
                // Only the caller reports "connected"; the callee's CallKit
                // answer-action fulfillment already marks the call connected.
                if wasOutgoing { CallKitManager.shared.reportConnected(callId: call.id) }
                #endif
            }
        default:
            teardown()
        }
    }

    // MARK: - Multi-device handoff

    /// True when a call is live on another of this user's devices and could be
    /// pulled to this one. Drives the "Move call here" pill.
    var canHandoff: Bool {
        guard let c = currentCall else { return false }
        return c.status == .active && phase == .idle
            && c.acceptingDeviceId != nil
            && c.acceptingDeviceId != DeviceIdentityManager.deviceId
    }

    var handoffDeviceLabel: String { currentCall?.acceptingDeviceName ?? "another device" }

    /// Moves the active call from the sibling device to this one.
    func handoffHere() async {
        guard let call = currentCall, canHandoff else { return }
        do {
            let ice = try await api.iceConfig(userId: userId)
            callService.start(iceServers: ice, video: call.type == .video)
            callService.setActiveCall(call)
            // The device pulling the call drives a fresh negotiation (it's the offerer).
            signaling.bind(callId: call.id, peerUserId: call.peerId(for: userId), isCaller: true)
            try await api.handoff(callId: call.id, userId: userId, newDeviceId: DeviceIdentityManager.deviceId)
            _ = await callService.createOffer()
            phase = .active
        } catch {
            AlertManager.shared.showAlert(title: "Handoff Failed", message: error.localizedDescription)
            teardown()
        }
    }

    // MARK: - Actions

    /// Places an outgoing call to `peer` within `roomId`.
    func placeCall(peer: ChatUser, roomId: String, type: CallType) async {
        guard phase == .idle, !userId.isEmpty else { return }
        do {
            let callId = try await api.initiate(callerId: userId, calleeId: peer.id, roomId: roomId, type: type)
            let call = Call(id: callId, callerId: userId, calleeId: peer.id, roomId: roomId,
                            type: type, status: .ringing, startedAt: Date(), peerName: peer.displayName)
            currentCall = call
            peerName = peer.displayName
            phase = .outgoing

            let ice = try await api.iceConfig(userId: userId)
            callService.start(iceServers: ice, video: type == .video)
            callService.setActiveCall(call)
            signaling.bind(callId: callId, peerUserId: peer.id, isCaller: true)
            _ = await callService.createOffer()

            #if os(iOS)
            CallKitManager.shared.reportOutgoing(callId: callId, calleeName: peer.displayName, hasVideo: type == .video)
            #endif
        } catch {
            AlertManager.shared.showAlert(title: "Call Failed", message: error.localizedDescription)
            teardown()
        }
    }

    /// Answers the current incoming call.
    func accept() async {
        guard let call = currentCall, phase == .incoming else { return }
        do {
            let ice = try await api.iceConfig(userId: userId)
            callService.start(iceServers: ice, video: call.type == .video)
            callService.setActiveCall(call)
            signaling.bind(callId: call.id, peerUserId: call.callerId, isCaller: false)
            try await api.accept(callId: call.id, userId: userId, acceptingDeviceId: DeviceIdentityManager.deviceId)
            phase = .active
        } catch {
            AlertManager.shared.showAlert(title: "Couldn't Answer", message: error.localizedDescription)
            teardown()
        }
    }

    /// Declines the current incoming call.
    func reject() async {
        guard let call = currentCall else { return }
        try? await api.reject(callId: call.id, userId: userId, acceptingDeviceId: DeviceIdentityManager.deviceId)
        teardown()
    }

    /// Ends/cancels the active or outgoing call.
    func end() async {
        guard let call = currentCall else { teardown(); return }
        if phase == .outgoing {
            try? await api.cancel(callId: call.id, userId: userId)
        } else {
            try? await api.end(callId: call.id, userId: userId)
        }
        teardown()
    }

    // MARK: - Teardown

    private func teardown() {
        let endedId = currentCall?.id
        callService.tearDown()
        signaling.unbind()
        callService.setActiveCall(nil)
        currentCall = nil
        phase = .idle
        #if os(iOS)
        if let endedId { CallKitManager.shared.end(callId: endedId) }
        #endif
    }
}
