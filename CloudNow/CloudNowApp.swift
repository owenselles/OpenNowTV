//
//  CloudNowApp.swift
//  CloudNow
//
//  Created by Owen Selles on 11/04/2026.
//

import BackgroundTasks
import SwiftUI

@main
struct CloudNowApp: App {
    @State private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environment(authManager)
            .onAppear { registerBGTasks() }
            .task { await authManager.initialize() }
        }
    }

    private func registerBGTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.owenselles.CloudNow.tokenRefresh",
            using: nil
        ) { task in
            Task { @MainActor in
                await authManager.refreshIfNeeded()
                authManager.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: true)
            }
        }
    }
}
