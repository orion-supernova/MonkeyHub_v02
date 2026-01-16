import Foundation
import CloudKit

/// Centralized manager for CloudKit notification subscriptions
/// Single Responsibility: Track and manage subscription lifecycle
@MainActor
final class NotificationSubscriptionManager: ObservableObject {
    static let shared = NotificationSubscriptionManager()
    
    // MARK: - State
    
    /// Track which rooms are currently subscribed (in-memory cache)
    private var activeSubscriptions: Set<String> = []
    
    /// Pending subscription operations (prevent concurrent subscribes)
    private var pendingOperations: [String: Task<Void, Never>] = [:]
    
    private let cloudKit = CloudKitManager.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Subscribe to messages in a room (idempotent - safe to call multiple times)
    /// - Parameter roomId: The room to subscribe to
    func subscribeToRoom(_ roomId: String) async {
        // Already subscribed? Skip
        if activeSubscriptions.contains(roomId) {
            print("✅ NotificationSubscriptionManager: Already subscribed to room \(roomId)")
            return
        }
        
        // Already subscribing? Wait for existing operation
        if let existingTask = pendingOperations[roomId] {
            print("⏳ NotificationSubscriptionManager: Waiting for existing subscription to \(roomId)")
            await existingTask.value
            return
        }
        
        // Create new subscription task
        let task = Task { @MainActor in
            await performSubscription(roomId: roomId)
        }
        
        pendingOperations[roomId] = task
        await task.value
        pendingOperations[roomId] = nil
    }
    
    /// Unsubscribe from messages and reactions in a room
    /// - Parameter roomId: The room to unsubscribe from
    func unsubscribeFromRoom(_ roomId: String) async {
        // Not subscribed? Skip
        guard activeSubscriptions.contains(roomId) else {
            print("ℹ️ NotificationSubscriptionManager: Not subscribed to room \(roomId), skipping unsubscribe")
            return
        }

        // Try to unsubscribe from messages (ignore errors if subscription doesn't exist)
        do {
            try await cloudKit.unsubscribeFromMessages(in: roomId)
            print("✅ NotificationSubscriptionManager: Unsubscribed from messages in room \(roomId)")
        } catch {
            print("⚠️ NotificationSubscriptionManager: Failed to unsubscribe from messages (might not exist): \(error)")
        }

        // Try to unsubscribe from reactions (ignore errors if subscription doesn't exist)
        do {
            try await cloudKit.unsubscribeFromReactions(in: roomId)
            print("✅ NotificationSubscriptionManager: Unsubscribed from reactions in room \(roomId)")
        } catch {
            print("⚠️ NotificationSubscriptionManager: Failed to unsubscribe from reactions (might not exist): \(error)")
        }

        activeSubscriptions.remove(roomId)
        print("✅ NotificationSubscriptionManager: Removed room \(roomId) from active subscriptions")
    }
    
    /// Check if currently subscribed to a room
    /// - Parameter roomId: The room ID to check
    /// - Returns: True if subscribed
    func isSubscribed(to roomId: String) -> Bool {
        return activeSubscriptions.contains(roomId)
    }
    
    /// Subscribe to all rooms the user has joined (typically called on app launch)
    func subscribeToAllJoinedRooms() async {
        print("📱 NotificationSubscriptionManager: Subscribing to all joined rooms...")
        
        do {
            let rooms = try await cloudKit.fetchUserRooms()
            
            // Subscribe in parallel for better performance
            await withTaskGroup(of: Void.self) { group in
                for room in rooms {
                    group.addTask { @MainActor in
                        await self.subscribeToRoom(room.id)
                    }
                }
            }
            
            print("✅ NotificationSubscriptionManager: Subscribed to \(rooms.count) rooms")
        } catch {
            print("❌ NotificationSubscriptionManager: Failed to fetch rooms: \(error)")
        }
    }
    
    /// Clear all subscription state (useful for logout or testing)
    func clearSubscriptionCache() {
        activeSubscriptions.removeAll()
        print("🧹 NotificationSubscriptionManager: Cleared subscription cache")
    }

    /// Force resubscribe to all joined rooms (useful for fixing notification issues)
    /// This clears the local cache and resubscribes to all rooms
    func forceResubscribeToAllRooms() async {
        print("🔄 NotificationSubscriptionManager: Force resubscribing to all rooms...")

        // Clear local cache
        activeSubscriptions.removeAll()

        // Resubscribe to all rooms
        do {
            let rooms = try await cloudKit.fetchUserRooms()

            // Subscribe in parallel for better performance
            await withTaskGroup(of: Void.self) { group in
                for room in rooms {
                    group.addTask { @MainActor in
                        await self.subscribeToRoom(room.id)
                    }
                }
            }

            print("✅ NotificationSubscriptionManager: Force resubscribed to \(rooms.count) rooms")
        } catch {
            print("❌ NotificationSubscriptionManager: Failed to force resubscribe: \(error)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func performSubscription(roomId: String) async {
        var messageSubscriptionSuccess = false
        var reactionSubscriptionSuccess = false

        // Subscribe to messages (critical - must succeed)
        do {
            try await cloudKit.subscribeToMessages(in: roomId)
            messageSubscriptionSuccess = true
            print("✅ NotificationSubscriptionManager: Subscribed to messages in room \(roomId)")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Duplicate subscription - treat as success
            messageSubscriptionSuccess = true
            print("ℹ️ NotificationSubscriptionManager: Message subscription already exists for room \(roomId)")
        } catch {
            print("❌ NotificationSubscriptionManager: Failed to subscribe to messages in room \(roomId): \(error)")
        }

        // Subscribe to reactions (optional - failure won't prevent message subscription)
        do {
            try await cloudKit.subscribeToReactions(in: roomId)
            reactionSubscriptionSuccess = true
            print("✅ NotificationSubscriptionManager: Subscribed to reactions in room \(roomId)")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Duplicate subscription - treat as success
            reactionSubscriptionSuccess = true
            print("ℹ️ NotificationSubscriptionManager: Reaction subscription already exists for room \(roomId)")
        } catch {
            print("⚠️ NotificationSubscriptionManager: Failed to subscribe to reactions in room \(roomId): \(error)")
            // Don't fail - reactions are optional
        }

        // Mark as subscribed if at least messages succeeded
        if messageSubscriptionSuccess {
            activeSubscriptions.insert(roomId)
            print("✅ NotificationSubscriptionManager: Successfully subscribed to room \(roomId) (messages: ✓, reactions: \(reactionSubscriptionSuccess ? "✓" : "✗"))")
        } else {
            print("❌ NotificationSubscriptionManager: Failed to subscribe to room \(roomId)")
        }
    }
}