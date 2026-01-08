//
//  AppDelegate.swift
//  chatTest.20241220
//
//  Created by muratcankoc on 19/04/2025.
//

import UIKit
import UserNotifications
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        registerForPushNotifications()
        return true
    }
    
    func registerForPushNotifications() {
        UNUserNotificationCenter.current().delegate = self
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("Permission granted: \(granted)")
            guard granted else { return }
            
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Device Token: \(token)")

        // Store token locally
        UserDefaults.standard.set(token, forKey: "deviceToken")

        // Sync token to CloudKit asynchronously
        Task { @MainActor in
            await CloudKitManager.shared.updateDeviceToken(token)
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for notifications: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

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
            completionHandler([.banner, .sound, .badge])
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

    /// Handle background notifications
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

    /// Helper to broadcast chat message notifications to the active view models
    private func handleChatMessageNotification(userInfo: [AnyHashable: Any]) {
        print("🔔 Received notification payload: \(userInfo)")
        
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            print("⚠️ Not a CloudKit notification")
            return
        }
        
        guard let queryNotification = cloudKitNotification as? CKQueryNotification else {
            print("⚠️ Not a query notification (Type: \(cloudKitNotification.notificationType))")
            return
        }
        
        guard let recordFields = queryNotification.recordFields,
              let roomId = recordFields[ChatMessage.roomIdKey] as? String else {
            print("⚠️ Missing roomId in notification fields. Available fields: \(queryNotification.recordFields ?? [:])")
            return
        }

        print("🚀 Broadcasting internal update for room: \(roomId)")
        
        // Pass the full record fields so ViewModel can update instantly
        var messageData = recordFields
        messageData["recordID"] = queryNotification.recordID?.recordName
        
        NotificationCenter.default.post(
            name: NSNotification.Name("DidReceiveChatMessage"),
            object: nil,
            userInfo: [
                "roomId": roomId,
                "messageData": messageData
            ]
        )
    }
}
