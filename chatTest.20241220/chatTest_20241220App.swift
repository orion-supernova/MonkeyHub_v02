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
    private let appDelegate = AppDelegate()

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var uiAppDelegate
    #endif

    init() {
        #if !canImport(UIKit)
        appDelegate.registerForPushNotifications()
        #endif
    }

    private var activeNotification: Notification.Name {
        #if canImport(UIKit)
        return UIApplication.didBecomeActiveNotification
        #else
        return NSApplication.didBecomeActiveNotification
        #endif
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
