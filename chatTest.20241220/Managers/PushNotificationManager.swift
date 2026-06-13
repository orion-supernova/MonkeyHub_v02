//
//  PushNotificationManager.swift
//  chatTest.20241220
//
//  Manages push notification registration via OneSignal (iOS SDK v5.x).
//
//  The only job of this file is to call OneSignal.login(userId) at the right times
//  so the device's push subscription is always linked to the authenticated user.
//  The SDK handles APNs token registration, environment detection, and opt-in state.

import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
#if os(iOS)
import OneSignalFramework

// MARK: - Subscription observer

/// Fires whenever OneSignal creates or changes the push subscription on this device
/// (e.g. new APNs token after an Xcode ↔ TestFlight environment switch).
/// Re-calls login() so the new subscription is always linked to the current user.
private final class PushSubscriptionObserver: NSObject, OSPushSubscriptionObserver {
    func onPushSubscriptionDidChange(state: OSPushSubscriptionChangedState) {
        guard let subId = state.current.id else { return }
        guard let userId = ConvexAuthService.storedUserId, !userId.isEmpty else {
            Swift.print("PushNotificationManager ⚠️ subscription ready (\(subId)) but no userId in Keychain")
            return
        }
        DispatchQueue.main.async {
            OneSignal.login(userId)
            Swift.print("PushNotificationManager ✅ subscription changed (\(subId)) → re-linked \(userId)")
        }
    }
}
#endif

// MARK: - Manager

@MainActor
final class PushNotificationManager {

    static let shared = PushNotificationManager()
    private init() {}

    private let oneSignalAppId = "c191a9f0-15cf-402a-8a04-dcc16108f4b0"

    #if os(iOS)
    private let subscriptionObserver = PushSubscriptionObserver()
    #endif

    // MARK: - Public API

    #if os(iOS)
    func initialize(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        OneSignal.initialize(oneSignalAppId, withLaunchOptions: launchOptions)

        // Register observer before login so any subscription change during init is caught.
        OneSignal.User.pushSubscription.addObserver(subscriptionObserver)

        // Link the authenticated user to this device's subscription.
        // login() is idempotent — safe to call on every launch.
        if let userId = ConvexAuthService.storedUserId, !userId.isEmpty {
            OneSignal.login(userId)
            Swift.print("PushNotificationManager ✅ login on launch — userId: \(userId)")
        } else {
            Swift.print("PushNotificationManager ℹ️ no stored userId — will login after sign-in")
        }

        OneSignal.Notifications.requestPermission({ accepted in
            Swift.print("PushNotificationManager ℹ️ push permission accepted = \(accepted)")
        }, fallbackToSettings: true)
    }
    #else
    func initialize(launchOptions: [AnyHashable: Any]?) {}
    #endif

    /// Call after successful sign-in with the Convex user ID.
    func setExternalUserId(_ userId: String) {
        #if os(iOS)
        OneSignal.login(userId)
        Swift.print("PushNotificationManager ✅ setExternalUserId → login(\(userId))")
        #endif
    }

    func logout() {
        #if os(iOS)
        OneSignal.logout()
        Swift.print("PushNotificationManager ℹ️ logout")
        #endif
    }

    func syncStoredTokenIfNeeded() {}

    /// Toggles push delivery for this device via OneSignal's subscription opt-in/out.
    func setNotificationsEnabled(_ enabled: Bool) {
        #if os(iOS)
        if enabled {
            OneSignal.User.pushSubscription.optIn()
        } else {
            OneSignal.User.pushSubscription.optOut()
        }
        Swift.print("PushNotificationManager ℹ️ notifications \(enabled ? "opted in" : "opted out")")
        #endif
    }

    func handleIncomingPush(_ userInfo: [AnyHashable: Any]) {
        ChatRepository.shared.handleIncomingPush(userInfo)
    }

    func clearBadge() {
        BadgeManager.shared.updateBadge(count: 0)
    }
}
