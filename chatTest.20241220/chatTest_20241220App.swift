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

    var body: some View {
        if auth.isAuthenticated {
            BaseView()
        } else {
            LoginView()
        }
    }
}

let userDefaults = UserDefaults.standard
let userIdUserDefaultsKey = "userId"
