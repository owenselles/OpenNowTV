//
//  OpenTVPlayApp.swift
//  OpenTVPlay
//
//  Created by Owen Selles on 11/04/2026.
//

import SwiftUI

@main
struct OpenTVPlayApp: App {
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
            .task { await authManager.initialize() }
        }
    }
}
