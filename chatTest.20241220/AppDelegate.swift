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

#if canImport(UIKit)
typealias BaseAppDelegate = UIApplicationDelegate
#else
protocol BaseAppDelegate {}
#endif

/// AppDelegate: Register for notifications and route them to ChatRepository.
/// Real-time data arrives via Convex WebSocket — push is used only for background
/// badge updates and deep-link navigation.
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
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("✅ Device Token: \(token)")

        UserDefaults.standard.set(token, forKey: "deviceToken")

        // Register token with Convex so backend can send APNs pushes
        Task { @MainActor in
            await ConvexAuthService.shared.registerDeviceToken(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for notifications: \(error.localizedDescription)")
    }
    #else
    func registerForPushNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("✅ macOS notification permission granted: \(granted)")
        }
        registerNotificationCategories()
    }
    #endif

    // MARK: - Notification Categories

    private func registerNotificationCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_ACTION",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a message..."
        )
        let messageCategory = UNNotificationCategory(
            identifier: "CHAT_MESSAGE",
            actions: [replyAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([messageCategory])
        print("✅ Registered notification category with Reply action")
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        Task { @MainActor in
            router.route(userInfo)
        }

        if router.shouldSuppressUI(for: userInfo) {
            completionHandler([])
            print("🔕 Notification UI suppressed — user in active chatroom")
        } else if router.isSystemMessage(userInfo) {
            completionHandler([])
            print("🔕 System message — silent notification")
        } else {
            completionHandler([.banner, .sound, .badge])
            print("🔔 Notification presented in foreground")
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "REPLY_ACTION":
            if let textResponse = response as? UNTextInputNotificationResponse {
                handleQuickReply(userInfo: userInfo, text: textResponse.userText)
            }

        case UNNotificationDefaultActionIdentifier:
            Task { @MainActor in
                router.route(userInfo)
                if let roomId = router.extractRoomId(from: userInfo) {
                    navigateToChatRoom(roomId: roomId)
                }
            }

        default:
            break
        }

        completionHandler()
    }

    // MARK: - Background Notifications

    #if canImport(UIKit)
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📲 Received remote notification in background")
        Task { @MainActor in
            router.route(userInfo)
        }
        completionHandler(.newData)
    }
    #endif

    // MARK: - Notification Action Handlers

    private func handleQuickReply(userInfo: [AnyHashable: Any], text: String) {
        guard let roomId = router.extractRoomId(from: userInfo) else { return }

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
