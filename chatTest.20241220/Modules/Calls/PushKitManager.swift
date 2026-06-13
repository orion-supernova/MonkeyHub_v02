import Foundation
#if os(iOS)
import PushKit

/// Registers a PushKit VoIP token with the backend and, when a VoIP push wakes
/// the app, reports the incoming call to CallKit synchronously (required by iOS).
@MainActor
final class PushKitManager: NSObject, ObservableObject {
    static let shared = PushKitManager()

    private var registry: PKPushRegistry?
    private var userId: String = ""

    private override init() { super.init() }

    /// Begins VoIP token registration for the signed-in user.
    func register(userId: String) {
        self.userId = userId
        if registry == nil {
            let registry = PKPushRegistry(queue: .main)
            registry.delegate = self
            registry.desiredPushTypes = [.voIP]
            self.registry = registry
        } else if let token = registry?.pushToken(for: .voIP) {
            // Already have a token — re-register it for the new user.
            sendToken(token)
        }
    }

    func unregister() {
        userId = ""
    }

    private func sendToken(_ tokenData: Data) {
        guard !userId.isEmpty else { return }
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        let uid = userId
        Task { try? await ConvexCallsAPI.shared.setVoipToken(userId: uid, token: token) }
    }
}

extension PushKitManager: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let data = pushCredentials.token
        Task { @MainActor in self.sendToken(data) }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }
        let dict = payload.dictionaryPayload
        let callId = (dict["callId"] as? String) ?? ""
        let callerName = (dict["callerName"] as? String) ?? "Incoming Call"
        let isVideo = (dict["type"] as? String) == "video"

        Task { @MainActor in
            // Report to CallKit immediately so iOS shows the ringer even if the
            // app was killed. CallController will hydrate the call via its
            // activeCallForUser subscription once the WebSocket reconnects.
            CallKitManager.shared.reportIncoming(callId: callId, callerName: callerName, hasVideo: isVideo) {
                completion()
            }
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {}
}
#endif
