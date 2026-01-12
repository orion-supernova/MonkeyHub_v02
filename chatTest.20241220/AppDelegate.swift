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

class AppDelegate: NSObject, BaseAppDelegate, UNUserNotificationCenterDelegate {

    // Deduplication tracker for CloudKit notifications
    private var processedNotificationIDs = Set<String>()
    private var processedRecordIDs = Set<String>()
    private var lastCleanupDate = Date()

    #if canImport(UIKit)
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        registerForPushNotifications()
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
    }
    #endif

    // MARK: - UNUserNotificationCenterDelegate
    // Note: This delegate is cross-platform (supported on macOS)

    /// Handle notification when app is in FOREGROUND
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        
        // Broadcast for real-time updates even if suppressed or presented
        handleChatMessageNotification(userInfo: userInfo)

        // Check if user is currently viewing this chatroom
        if shouldSuppressNotification(userInfo: userInfo) {
            // Silent: Don't show banner/sound
            completionHandler([])
            print("Notification suppressed - user in active chatroom")
        } else {
            // Show banner and play sound
            #if canImport(UIKit)
            completionHandler([.banner, .sound, .badge])
            #else
            completionHandler([.banner, .sound, .badge]) // Also works on macOS
            #endif
            print("Notification presented in foreground")
        }
    }

    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo),
           let queryNotification = cloudKitNotification as? CKQueryNotification,
           let recordFields = queryNotification.recordFields,
           let roomId = recordFields[ChatMessage.roomIdKey] as? String {

            print("User tapped notification for room: \(roomId)")

            // Navigate to chatroom
            Task { @MainActor in
                await navigateToChatRoom(roomId: roomId)
            }
        }

        completionHandler()
    }

    /// Check if notification should be suppressed
    private func shouldSuppressNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let queryNotification = cloudKitNotification as? CKQueryNotification,
              let recordFields = queryNotification.recordFields,
              let roomId = recordFields[ChatMessage.roomIdKey] as? String else {
            return false
        }

        // Check if user is currently in this chatroom
        let navigationState = NavigationStateManager.shared
        return navigationState.currentScreen == .chatRoom &&
               navigationState.currentRoomId == roomId
    }

    /// Navigate to specific chatroom
    @MainActor
    private func navigateToChatRoom(roomId: String) async {
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenChatRoom"),
            object: nil,
            userInfo: ["roomId": roomId]
        )
    }

    #if canImport(UIKit)
    /// Handle background notifications (iOS specific)
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("Received remote notification")

        // Broadcast for real-time updates
        handleChatMessageNotification(userInfo: userInfo)

        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            if notification.notificationType == .query {
                completionHandler(.newData)
                return
            }
        }

        completionHandler(.noData)
    }
    #endif

    /// Helper (Cross-platform)
    private func handleChatMessageNotification(userInfo: [AnyHashable: Any]) {
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return
        }
        
        // Use notificationID to deduplicate multiple calls for the same event
        if let id = cloudKitNotification.notificationID {
            let notificationID = "\(id)"
            if processedNotificationIDs.contains(notificationID) {
                print("♻️ Skipping already processed notificationID: \(notificationID)")
                return
            }
            processedNotificationIDs.insert(notificationID)
            print("🆕 Processing new notificationID: \(notificationID)")
            
            // Periodically clean up old IDs (every 10 seconds)
            if Date().timeIntervalSince(lastCleanupDate) > 10 {
                processedNotificationIDs.removeAll()
                processedRecordIDs.removeAll()
                lastCleanupDate = Date()
            }
        }

        guard let queryNotification = cloudKitNotification as? CKQueryNotification else {
            return
        }
        
        // Secondary deduplication by Record ID (most reliable)
        if let recordID = queryNotification.recordID?.recordName {
            if processedRecordIDs.contains(recordID) {
                print("♻️ Skipping already processed recordID: \(recordID)")
                return
            }
            processedRecordIDs.insert(recordID)
        }

        guard let recordFields = queryNotification.recordFields,
              let roomId = recordFields[ChatMessage.roomIdKey] as? String else {
            print("⚠️ Missing roomId in notification fields")
            return
        }

        print("🚀 Passing valid notification data to ChatRepository for room: \(roomId)")
        
        // Pass the raw userInfo (validated by deduplication) to the Repository
        Task { @MainActor in
            ChatRepository.shared.handleIncomingNotification(userInfo)
        }
    }
}
