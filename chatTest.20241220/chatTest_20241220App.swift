//
//  chatTest_20241220App.swift
//  chatTest.20241220
//
//  Created by muratcankoc on 20/12/2024.
//

import SwiftUI

@main
struct chatTest_20241220App: App {
    @StateObject private var auth = ConvexAuthService.shared

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var uiAppDelegate
    #endif

    init() {
        // Restore theme from Keychain so it survives reinstalls.
        // @AppStorage uses UserDefaults which is wiped on fresh install,
        // but Keychain persists. Seed UserDefaults if it hasn't been set yet.
        if UserDefaults.standard.string(forKey: "selectedTheme") == nil,
           let saved = KeychainService.get("selectedTheme") {
            UserDefaults.standard.set(saved, forKey: "selectedTheme")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(auth)
                .withAlertManager()
        }
    }
}

struct MainView: View {
    @EnvironmentObject var auth: ConvexAuthService
    @AppStorage(AppearanceKeys.captureProtection) private var captureProtection = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if auth.isAuthenticated {
                BaseView()
                    .overlay { CallOverlayHost() }
            } else {
                LoginView()
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) { ConnectionBanner(); Spacer() }
                .animation(.spring(response: 0.3), value: ConnectionMonitor.shared.isOnline)
        }
        .sensitiveContentProtection(enabled: captureProtection)
        .onChange(of: scenePhase) { _, phase in
            guard auth.isAuthenticated, let userId = auth.currentUserId else { return }
            let status: String
            switch phase {
            case .active: status = "online"
            // Background/inactive map to "away"; "offline" is reserved for
            // explicit logout (auth:logout) so a locked phone isn't shown as
            // signed-out to peers.
            case .inactive, .background: status = "away"
            @unknown default: status = "online"
            }
            Task { try? await ConvexChatAPI.shared.updateStatus(userId: userId, status: status) }
        }
    }
}

let userDefaults = UserDefaults.standard
let userIdUserDefaultsKey = "userId"
