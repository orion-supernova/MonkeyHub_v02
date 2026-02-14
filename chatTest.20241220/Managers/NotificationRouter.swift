import Foundation
import CloudKit
import UserNotifications

/// Single responsibility: Parse CloudKit notifications and route to appropriate handlers
/// This class does NOT handle data updates - it only routes to the correct manager
@MainActor
final class NotificationRouter {
    static let shared = NotificationRouter()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Route incoming notification to appropriate handler
    /// - Parameter userInfo: The notification payload from CloudKit
    func route(_ userInfo: [AnyHashable: Any]) {
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let queryNotification = cloudKitNotification as? CKQueryNotification else {
            print("⚠️ NotificationRouter: Invalid notification format")
            return
        }
        
        // Route based on subscription ID
        if let subscriptionID = queryNotification.subscriptionID {
            if subscriptionID.hasPrefix("typing-") {
                routeToTypingManager(userInfo: userInfo, queryNotification: queryNotification)
                return
            } else if subscriptionID.hasPrefix("messages-") {
                routeToChatRepository(userInfo: userInfo, queryNotification: queryNotification)
                return
            } else if subscriptionID.hasPrefix("reactions-") {
                routeToReactionHandler(userInfo: userInfo, queryNotification: queryNotification)
                return
            } else if subscriptionID.hasPrefix("room-changes-") {
                routeToRoomChangeHandler(userInfo: userInfo, queryNotification: queryNotification)
                return
            } else if subscriptionID.hasPrefix("my-rooms-") {
                routeToMyRoomsHandler(queryNotification: queryNotification)
                return
            }
        }
        
        // Fallback: Try to determine by record fields
        if let recordFields = queryNotification.recordFields,
           recordFields[ChatMessage.roomIdKey] != nil {
            routeToChatRepository(userInfo: userInfo, queryNotification: queryNotification)
        }
    }
    
    /// Check if notification should suppress UI (banner/sound)
    /// - Parameter userInfo: The notification payload
    /// - Returns: True if notification should be silent (user is viewing that room)
    nonisolated func shouldSuppressUI(for userInfo: [AnyHashable: Any]) -> Bool {
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let queryNotification = cloudKitNotification as? CKQueryNotification,
              let recordFields = queryNotification.recordFields,
              let roomId = recordFields[ChatMessage.roomIdKey] as? String else {
            return false
        }
        
        // Check if user is currently viewing this chatroom
        // Access shared instance without isolation since we're only reading Published properties
        let navigationState = NavigationStateManager.shared
        return navigationState.currentScreen == .chatRoom &&
               navigationState.currentRoomId == roomId
    }
    
    /// Extract room ID from notification for navigation
    /// - Parameter userInfo: The notification payload
    /// - Returns: Room ID if available
    nonisolated func extractRoomId(from userInfo: [AnyHashable: Any]) -> String? {
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let queryNotification = cloudKitNotification as? CKQueryNotification,
              let recordFields = queryNotification.recordFields,
              let roomId = recordFields[ChatMessage.roomIdKey] as? String else {
            return nil
        }
        return roomId
    }

    /// Check if notification is for a system message (should be silent)
    /// - Parameter userInfo: The notification payload
    /// - Returns: True if this is a system message
    nonisolated func isSystemMessage(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let queryNotification = cloudKitNotification as? CKQueryNotification,
              let recordFields = queryNotification.recordFields,
              let messageType = recordFields[ChatMessage.typeKey] as? String else {
            return false
        }
        return messageType == MessageType.system.rawValue
    }
    
    // MARK: - Private Routing
    
    private func routeToChatRepository(userInfo: [AnyHashable: Any], queryNotification: CKQueryNotification) {
        guard let recordFields = queryNotification.recordFields,
              let roomId = recordFields[ChatMessage.roomIdKey] as? String else {
            print("⚠️ NotificationRouter: Missing roomId in message notification")
            return
        }
        
        print("📥 NotificationRouter: Routing message notification to ChatRepository (room: \(roomId))")
        ChatRepository.shared.handleIncomingNotification(userInfo)
    }
    
    private func routeToTypingManager(userInfo: [AnyHashable: Any], queryNotification: CKQueryNotification) {
        print("📥 NotificationRouter: Routing typing notification to TypingIndicatorManager")
        TypingIndicatorManager.shared.handleTypingNotification(userInfo)
    }

    private func routeToReactionHandler(userInfo: [AnyHashable: Any], queryNotification: CKQueryNotification) {
        guard let recordFields = queryNotification.recordFields,
              let messageId = recordFields[MessageReaction.messageIdKey] as? String else {
            print("⚠️ NotificationRouter: Missing messageId in reaction notification")
            return
        }

        print("📥 NotificationRouter: Routing reaction notification to ChatRepository (message: \(messageId))")
        ChatRepository.shared.handleIncomingReaction(userInfo, queryNotification: queryNotification)
    }

    private func routeToMyRoomsHandler(queryNotification: CKQueryNotification) {
        // This fires when any room where user is a participant changes (create, update, delete)
        // Used for same-account multi-device sync
        print("📥 NotificationRouter: My rooms changed, refreshing room list")

        Task {
            await ChatRepository.shared.fetchRooms()
        }
    }

    private func routeToRoomChangeHandler(userInfo: [AnyHashable: Any], queryNotification: CKQueryNotification) {
        guard let recordFields = queryNotification.recordFields,
              let roomId = recordFields[ChatRoom.idKey] as? String else {
            // For deletions, recordFields might be nil but we can get roomId from subscription
            if let subscriptionID = queryNotification.subscriptionID,
               subscriptionID.hasPrefix("room-changes-") {
                let roomId = String(subscriptionID.dropFirst("room-changes-".count))
                print("📥 NotificationRouter: Routing room deletion notification (room: \(roomId))")
                ChatRepository.shared.handleRoomChange(userInfo, queryNotification: queryNotification, roomId: roomId)
                return
            }
            print("⚠️ NotificationRouter: Missing roomId in room change notification")
            return
        }

        print("📥 NotificationRouter: Routing room change notification (room: \(roomId))")
        ChatRepository.shared.handleRoomChange(userInfo, queryNotification: queryNotification, roomId: roomId)
    }
}