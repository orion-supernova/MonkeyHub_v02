import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Manages the application icon badge count.
/// Following SOLID principles: Single Responsibility for OS-level badge updates.
final class BadgeManager {
    static let shared = BadgeManager()

    private var currentCount = -1
    private init() {}

    /// Updates the application icon badge count — no-op if count hasn't changed.
    func updateBadge(count: Int) {
        let finalCount = max(0, count)
        guard finalCount != currentCount else { return }
        currentCount = finalCount
        UNUserNotificationCenter.current().setBadgeCount(finalCount) { error in
            if let error = error {
                print("❌ BadgeManager: Failed to update badge count: \(error.localizedDescription)")
            } else {
                print("✅ BadgeManager: Badge updated to \(finalCount)")
            }
        }
    }
    
    /// Clears the application icon badge count
    func clearBadge() {
        updateBadge(count: 0)
    }
}
