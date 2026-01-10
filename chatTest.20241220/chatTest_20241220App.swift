//
//  chatTest_20241220App.swift
//  chatTest.20241220
//
//  Created by muratcankoc on 20/12/2024.
//

import CloudKit
import SwiftUI

@main
struct chatTest_20241220App: App {
    @StateObject private var cloudKit = CloudKitManager.shared
    
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    private var activeNotification: Notification.Name {
        #if canImport(UIKit)
        return UIApplication.didBecomeActiveNotification
        #else
        return NSApplication.didBecomeActiveNotification
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            // The view that checks for iCloud status and shows different views
            MainView()
                .environmentObject(cloudKit)
                .onReceive(NotificationCenter.default.publisher(for: activeNotification)) { _ in
                    // Trigger the initialization of CloudKit whenever the app becomes active
                    Task {
                        await cloudKit.initialize()
                    }
                }
                .withAlertManager()
        }
    }
}

struct MainView: View {
    @EnvironmentObject var cloudKit: CloudKitManager

    var body: some View {
        if !cloudKit.isInitialized {
            LoadingView()
        } else {
            switch cloudKit.iCloudStatus {
            case .available:
                let isLocallyAuthenticated = userDefaults.string(forKey: userIdUserDefaultsKey) != nil
                
                if cloudKit.isAuthenticated || isLocallyAuthenticated {
                    BaseView()
                        .onAppear {
                            if !cloudKit.isAuthenticated {
                                cloudKit.isAuthenticated = true
                            }
                        }
                } else {
                    LoginView()
                }
            case .noAccount:
                ICloudErrorView(message: "Please sign in to iCloud in Settings")
            case .restricted:
                ICloudErrorView(message: "iCloud access is restricted")
            case .noInternet:
                ICloudErrorView(message: "Please check your internet connection")
            case .error(let error):
                ICloudErrorView(message: error.localizedDescription)
            case .unknown:
                LoadingView()
            case .temporarilyUnavailable:
                ICloudErrorView(
                    message: "iCloud is temporarily unavailable. Please try again later"
                )
            }
        }
    }
}

let userDefaults = UserDefaults.standard
let userIdUserDefaultsKey = "userId"
