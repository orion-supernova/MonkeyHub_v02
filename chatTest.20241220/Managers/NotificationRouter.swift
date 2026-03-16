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
        guard let roomId = userInfo["roomId"] as? String else { return false }
        let nav = NavigationStateManager.shared
        return nav.currentScreen == .chatRoom && nav.currentRoomId == roomId
    }

    /// Extract the room ID from a push notification payload.
    nonisolated func extractRoomId(from userInfo: [AnyHashable: Any]) -> String? {
        return userInfo["roomId"] as? String
    }

    /// Returns true if this is a system message (should be delivered silently).
    nonisolated func isSystemMessage(_ userInfo: [AnyHashable: Any]) -> Bool {
        return (userInfo["type"] as? String) == MessageType.system.rawValue
    }
}
