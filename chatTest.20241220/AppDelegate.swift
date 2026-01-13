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
        
        // Route data update
        Task { @MainActor in
            router.route(userInfo)
            
            // Navigate to chatroom if applicable
            if let roomId = router.extractRoomId(from: userInfo) {
                print("👆 User tapped notification for room: \(roomId)")
                navigateToChatRoom(roomId: roomId)
            }
        }

        completionHandler()
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