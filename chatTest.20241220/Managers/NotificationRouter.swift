import Foundation
import UserNotifications

/// Routes incoming push notifications to the appropriate handler.
/// With Convex, real-time data arrives via WebSocket. Push is used only for
/// background badge updates and room-preview refreshes.
@MainActor
final class NotificationRouter {
    static let shared = NotificationRouter()

    private init() {}

    // MARK: - Public API

    /// Route incoming notification payload.
    func route(_ userInfo: [AnyHashable: Any]) {
        ChatRepository.shared.handleIncomingPush(userInfo)
    }

    /// Returns true if notification UI (banner/sound) should be suppressed
    /// because the user is actively viewing the relevant chatroom.
    nonisolated func shouldSuppressUI(for userInfo: [AnyHashable: Any]) -> Bool {
        guard let roomId = extractRoomId(from: userInfo) else { return false }
        let nav = NavigationStateManager.shared
        return nav.currentScreen == .chatRoom && nav.currentRoomId == roomId
    }

    /// Extract the room ID from a push notification payload.
    /// OneSignal v5 may deliver userInfo with roomId at the top level
    /// (background/raw APNs) or nested under custom.a (foreground UNNotification).
    nonisolated func extractRoomId(from userInfo: [AnyHashable: Any]) -> String? {
        if let roomId = userInfo["roomId"] as? String, !roomId.isEmpty {
            return roomId
        }
        if let custom = userInfo["custom"] as? [AnyHashable: Any],
           let additionalData = custom["a"] as? [AnyHashable: Any],
           let roomId = additionalData["roomId"] as? String,
           !roomId.isEmpty {
            return roomId
        }
        return nil
    }

    /// Returns true if this is a system message (should be delivered silently).
    nonisolated func isSystemMessage(_ userInfo: [AnyHashable: Any]) -> Bool {
        let type1 = userInfo["type"] as? String
        let custom = userInfo["custom"] as? [AnyHashable: Any]
        let type2 = (custom?["a"] as? [AnyHashable: Any])?["type"] as? String
        return (type1 ?? type2) == MessageType.system.rawValue
    }
}
