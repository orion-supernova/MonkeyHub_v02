//
//  PushNotificationManager.swift
//  chatTest.20241220
//
//  Manages push notification registration via OneSignal (iOS SDK v5.x).
//
//  Responsibilities:
//    • Initialize OneSignal at app launch
//    • Associate the device with a user via OneSignal.login(_:) after sign-in
//    • Disassociate on sign-out via OneSignal.logout()
//    • Delegate incoming push payloads to ChatRepository.handleIncomingPush
//    • Clear the badge count on demand
//
//  OneSignal manages APNs device-token registration automatically.
//  No manual token storage or Convex mutation is needed for device tokens.

import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import OneSignalFramework
#endif

@MainActor
final class PushNotificationManager {

    // MARK: - Singleton

    static let shared = PushNotificationManager()
    private init() {}

    // MARK: - Constants

    private let oneSignalAppId = "c191a9f0-15cf-402a-8a04-dcc16108f4b0"

    // MARK: - Public API

    /// Initialize OneSignal. Call this from AppDelegate.didFinishLaunchingWithOptions.
    #if os(iOS)
    func initialize(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        OneSignal.initialize(oneSignalAppId, withLaunchOptions: launchOptions)
        OneSignal.Notifications.requestPermission({ accepted in
            print("PushNotificationManager: OneSignal permission accepted = \(accepted)")
        }, fallbackToSettings: true)
    }
    #else
    func initialize(launchOptions: [AnyHashable: Any]?) {
        // OneSignal not supported on macOS — no-op
    }
    #endif

    /// Associate this device with a user after successful login.
    /// OneSignal uses this external ID to target pushes to a specific user.
    func setExternalUserId(_ userId: String) {
        #if os(iOS)
        OneSignal.login(userId)
        print("PushNotificationManager: OneSignal login with externalId = \(userId)")
        #endif
    }

    /// Disassociate this device from the current user after sign-out.
    func logout() {
        #if os(iOS)
        OneSignal.logout()
        print("PushNotificationManager: OneSignal logout")
        #endif
    }

    /// No-op: kept for call-site backward compatibility.
    /// OneSignal manages token registration automatically — nothing to sync.
    func syncStoredTokenIfNeeded() {
        // No-op: OneSignal manages device token registration internally.
    }

    /// Forward an incoming push payload to ChatRepository.
    func handleIncomingPush(_ userInfo: [AnyHashable: Any]) {
        ChatRepository.shared.handleIncomingPush(userInfo)
    }

    /// Set the app-icon badge count to zero.
    func clearBadge() {
        BadgeManager.shared.updateBadge(count: 0)
    }
}
