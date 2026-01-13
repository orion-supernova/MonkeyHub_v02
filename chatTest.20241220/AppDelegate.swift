//
//  AppDelegate.swift
//  chatTest.20241220
//
//  Created by muratcankoc on 19/04/2025.
//

#if canImport(UIKit)
import UIKit
#endif
import UserNotifications
import CloudKit

#if canImport(UIKit)
typealias BaseAppDelegate = UIApplicationDelegate
#else
protocol BaseAppDelegate {}
#endif

/// AppDelegate: Single Responsibility - Register for notifications and route them
/// Does NOT handle deduplication or data updates - that's the Repository's job
class AppDelegate: NSObject, BaseAppDelegate, UNUserNotificationCenterDelegate {
    
    private let router = NotificationRouter.shared

    #if canImport(UIKit)
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        registerForPushNotifications()
        registerNotificationCategories()
        return true
    }

    func registerForPushNotifications() {
        UNUserNotificationCenter.current().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("✅ Notification permission granted: \(granted)")
            guard granted else {
                print("⚠️ User denied notification permissions")
                return
            }

            DispatchQueue.main.async {
                print("📱 Registering for remote notifications...")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("✅ Device Token: \(token)")

        // Store token locally
        UserDefaults.standard.set(token, forKey: "deviceToken")

        // Sync token to CloudKit asynchronously
        Task { @MainActor in
            await CloudKitManager.shared.updateDeviceToken(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for notifications: \(error.localizedDescription)")
    }
    #else
    // macOS doesn't support APNS device tokens
    // CloudKit silent notifications still work for background sync
    func registerForPushNotifications() {
        UNUserNotificationCenter.current().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("✅ macOS notification permission granted: \(granted)")
            print("ℹ️ Note: macOS doesn't use device tokens. CloudKit silent notifications will work.")
        }
        
        // Also register categories for macOS
        registerNotificationCategories()
    }
    #endif
    
    // MARK: - Rich Notification Setup
    
    /// Register notification categories with custom actions (buttons)
    private func registerNotificationCategories() {
        // Text input action - Quick reply (this is the only one that makes sense for now)
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_ACTION",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a message..."
        )
        
        // Category for all messages (text, images, videos)
        let messageCategory = UNNotificationCategory(
            identifier: "CHAT_MESSAGE",
            actions: [replyAction],  // Only Reply for now
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Register category
        UNUserNotificationCenter.current().setNotificationCategories([messageCategory])
        
        print("✅ Registered notification category with Reply action")
    }

    // MARK: - UNUserNotificationCenterDelegate (Cross-platform)

    /// Handle notification when app is in FOREGROUND
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        // Route to appropriate handler (Repository will deduplicate)
        Task { @MainActor in
            router.route(userInfo)
        }

        // Check if user is currently viewing this chatroom
        if router.shouldSuppressUI(for: userInfo) {
            // Silent: Don't show banner/sound (but data was still processed above)
            completionHandler([])
            print("🔕 Notification UI suppressed - user in active chatroom")
        } else {
            // Show banner and play sound
            #if canImport(UIKit)
            completionHandler([.banner, .sound, .badge])
            #else
            completionHandler([.banner, .sound, .badge]) // Also works on macOS
            #endif
            print("🔔 Notification presented in foreground")
        }
    }

    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle custom actions
        switch response.actionIdentifier {
        case "REPLY_ACTION":
            // User tapped "Reply" button
            if let textResponse = response as? UNTextInputNotificationResponse {
                let replyText = textResponse.userText
                handleQuickReply(userInfo: userInfo, text: replyText)
            }
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself (not a button)
            Task { @MainActor in
                router.route(userInfo)
                
                // Navigate to chatroom if applicable
                if let roomId = router.extractRoomId(from: userInfo) {
                    print("👆 User tapped notification for room: \(roomId)")
                    navigateToChatRoom(roomId: roomId)
                }
            }
            
        default:
            break
        }

        completionHandler()
    }
    
    // MARK: - Notification Action Handlers
    
    private func handleQuickReply(userInfo: [AnyHashable: Any], text: String) {
        guard let roomId = router.extractRoomId(from: userInfo) else { return }
        
        print("📤 Quick reply: \(text) to room \(roomId)")
        
        // Send message in background
        Task { @MainActor in
            let userId = UserDefaults.standard.string(forKey: "userId") ?? ""
            let userName = UserDefaults.standard.string(forKey: "userName") ?? "You"
            
            let message = ChatMessage(
                senderId: userId,
                senderName: userName,
                content: text,
                type: .text,
                roomId: roomId
            )
            
            await ChatRepository.shared.sendMessage(message)
        }
    }
    
    private func handleLikeAction(userInfo: [AnyHashable: Any]) {
        // Extract message ID and send "like" reaction
        print("❤️ User liked the message")
        // TODO: Implement reaction system
    }
    
    private func handleMarkAsRead(userInfo: [AnyHashable: Any]) {
        guard let roomId = router.extractRoomId(from: userInfo) else { return }
        
        print("✅ Marked room \(roomId) as read")
        
        // Clear unread count
        Task { @MainActor in
            ChatRepository.shared.unreadCounts[roomId] = 0
            BadgeManager.shared.updateBadge(count: ChatRepository.shared.unreadCounts.values.reduce(0, +))
        }
    }

    #if canImport(UIKit)
    /// Handle background notifications (iOS specific)
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📲 Received remote notification in background")

        // Route to appropriate handler (Repository will deduplicate)
        Task { @MainActor in
            router.route(userInfo)
        }

        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            if notification.notificationType == .query {
                completionHandler(.newData)
                return
            }
        }

        completionHandler(.noData)
    }
    #endif

    // MARK: - Navigation Helper
    
    @MainActor
    private func navigateToChatRoom(roomId: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenChatRoom"),
            object: nil,
            userInfo: ["roomId": roomId]
        )
    }
}