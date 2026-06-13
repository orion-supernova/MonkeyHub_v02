import Foundation
#if os(iOS)
import CallKit
import AVFoundation

/// Wraps CallKit so incoming/outgoing calls show the native system UI and the
/// app can be woken by VoIP pushes. Translates CallKit actions into callbacks
/// the `CallController` acts on. Maps CallKit `UUID` ↔ our string `callId`.
@MainActor
final class CallKitManager: NSObject, ObservableObject {
    static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()

    // Bridges between CallKit's UUID and our Convex call id.
    private var uuidToCallId: [UUID: String] = [:]
    private var callIdToUUID: [String: UUID] = [:]

    // Callbacks wired by CallController.
    var onAnswer: ((String) -> Void)?
    var onEnd: ((String) -> Void)?
    var onMute: ((String, Bool) -> Void)?

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    // MARK: - Reporting

    /// Reports an incoming call to the system (shows the full-screen ringer).
    /// Must be called synchronously from the VoIP push handler when woken.
    func reportIncoming(callId: String, callerName: String, hasVideo: Bool, completion: (() -> Void)? = nil) {
        let uuid = uuid(for: callId)
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.hasVideo = hasVideo
        update.localizedCallerName = callerName
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error { AppLogger.shared.logError("CallKit reportIncoming", error) }
            completion?()
        }
    }

    func reportOutgoing(callId: String, calleeName: String, hasVideo: Bool) {
        // Register the outgoing call with CallKit via a start-call transaction.
        // "connecting"/"connected" are then reported from the CXStartCallAction
        // delegate and reportConnected(_:) — not here (which would double-drive).
        let uuid = uuid(for: callId)
        let handle = CXHandle(type: .generic, value: calleeName)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.isVideo = hasVideo
        callController.request(CXTransaction(action: action)) { error in
            if let error { AppLogger.shared.logError("CallKit startCall", error) }
        }
    }

    func reportConnected(callId: String) {
        guard let uuid = callIdToUUID[callId] else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: nil)
    }

    /// Tears down the system call (used when the remote ends or we end locally).
    func end(callId: String) {
        guard let uuid = callIdToUUID[callId] else { return }
        let action = CXEndCallAction(call: uuid)
        callController.request(CXTransaction(action: action)) { _ in }
        forget(callId)
    }

    // MARK: - UUID mapping

    private func uuid(for callId: String) -> UUID {
        if let existing = callIdToUUID[callId] { return existing }
        let uuid = UUID()
        callIdToUUID[callId] = uuid
        uuidToCallId[uuid] = callId
        return uuid
    }

    private func forget(_ callId: String) {
        if let uuid = callIdToUUID[callId] {
            uuidToCallId[uuid] = nil
        }
        callIdToUUID[callId] = nil
    }
}

// MARK: - CXProviderDelegate

extension CallKitManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {}

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            if let callId = uuidToCallId[action.callUUID] { onAnswer?(callId) }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            if let callId = uuidToCallId[action.callUUID] {
                onEnd?(callId)
                forget(callId)
            }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            if let callId = uuidToCallId[action.callUUID] { onMute?(callId, action.isMuted) }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
        // Mark the system call as connecting now that it's registered.
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}
    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}
#endif
