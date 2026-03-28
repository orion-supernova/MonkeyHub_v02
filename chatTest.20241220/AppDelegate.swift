//
//  AppDelegate.swift
//  chatTest.20241220
//
//  Wires OneSignal initialization and routes foreground / background
//  notifications through NotificationRouter.
//  Real-time data arrives via the Convex WebSocket — push is used only for
//  background badge updates and deep-link navigation.

#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

#if canImport(UIKit)
typealias BaseAppDelegate = UIApplicationDelegate
#else
protocol BaseAppDelegate {}
#endif

class AppDelegate: NSObject, BaseAppDelegate, UNUserNotificationCenterDelegate {

    private let router = NotificationRouter.shared

    #if canImport(UIKit)
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerNotificationCategories()
        // OneSignal handles APNs registration and permission requests.
        // PushNotificationManager.initialize is responsible for all setup.
        PushNotificationManager.shared.initialize(launchOptions: launchOptions)
        // Set delegate AFTER OneSignal initializes so AppDelegate is the final
        // UNUserNotificationCenter delegate — ensuring willPresent and didReceive
        // are always routed through our own handlers.
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    #endif

    // MARK: - Background Remote Notifications
    // OneSignal intercepts didRegisterForRemoteNotificationsWithDeviceToken and
    // didFailToRegisterForRemoteNotificationsWithError automatically. We only
    // need the background fetch handler to forward payloads to ChatRepository.

    #if canImport(UIKit)
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            ChatRepository.shared.handleIncomingPush(userInfo)
        }
        completionHandler(.newData)
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
    }

    // MARK: - UNUserNotificationCenterDelegate (foreground delivery)

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
            completionHandler([.sound])
        } else if router.isSystemMessage(userInfo) {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound, .badge])
        }
    }

    // MARK: - UNUserNotificationCenterDelegate (user tapped notification)

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
