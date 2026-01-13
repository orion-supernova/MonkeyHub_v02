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
    
    /// Unsubscribe from messages in a room
    /// - Parameter roomId: The room to unsubscribe from
    func unsubscribeFromRoom(_ roomId: String) async {
        // Not subscribed? Skip
        guard activeSubscriptions.contains(roomId) else {
            print("ℹ️ NotificationSubscriptionManager: Not subscribed to room \(roomId), skipping unsubscribe")
            return
        }
        
        do {
            try await cloudKit.unsubscribeFromMessages(in: roomId)
            activeSubscriptions.remove(roomId)
            print("✅ NotificationSubscriptionManager: Unsubscribed from room \(roomId)")
        } catch {
            print("❌ NotificationSubscriptionManager: Failed to unsubscribe from room \(roomId): \(error)")
        }
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
    
    // MARK: - Private Helpers
    
    private func performSubscription(roomId: String) async {
        do {
            try await cloudKit.subscribeToMessages(in: roomId)
            activeSubscriptions.insert(roomId)
            print("✅ NotificationSubscriptionManager: Successfully subscribed to room \(roomId)")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Duplicate subscription - treat as success
            activeSubscriptions.insert(roomId)
            print("ℹ️ NotificationSubscriptionManager: Duplicate subscription to room \(roomId) (already exists on server)")
        } catch {
            print("❌ NotificationSubscriptionManager: Failed to subscribe to room \(roomId): \(error)")
        }
    }
}