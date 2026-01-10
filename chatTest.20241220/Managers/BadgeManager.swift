import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Manages the application icon badge count.
/// Following SOLID principles: Single Responsibility for OS-level badge updates.
final class BadgeManager {
    static let shared = BadgeManager()
    
    private init() {}
    
    /// Updates the application icon badge count
    /// - Parameter count: The new badge count (0 clears it)
    func updateBadge(count: Int) {
        let finalCount = max(0, count)
        
        // On iOS 16 and later, we should use UNUserNotificationCenter
        // Setting it to 0 clears the badge.
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
