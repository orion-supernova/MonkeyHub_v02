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
    
    var body: some Scene {
        WindowGroup {
            // The view that checks for iCloud status and shows different views
            MainView()
                .environmentObject(cloudKit)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didBecomeActiveNotification)
                ) { _ in
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
                if cloudKit.isAuthenticated {
                    BaseView()
                        .environmentObject(cloudKit)
                } else {
                    let isAuthenticated = userDefaults.string(forKey: userIdUserDefaultsKey)
                    if let isAuthenticated, !isAuthenticated.isEmpty {
                        BaseView()
                            .environmentObject(cloudKit)
                            .onAppear {
                                cloudKit.isAuthenticated = true
                            }
                    } else {
                        LoginView()
                            .environmentObject(cloudKit)
                    }
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
