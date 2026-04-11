import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) var authManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if authManager.isLoading {
                loadingView
            } else {
                loginPrompt
            }
        }
        .alert("Login Error", isPresented: .constant(authManager.loginError != nil), actions: {
            Button("Retry") {
                Task { await authManager.login() }
            }
            Button("Cancel", role: .cancel) {}
        }, message: {
            Text(authManager.loginError ?? "")
        })
    }

    // MARK: Login Prompt

    private var loginPrompt: some View {
        VStack(spacing: 48) {
            // App branding
            VStack(spacing: 12) {
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                Text("OpenTVPlay")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("GeForce NOW for Apple TV")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Sign in button (focus-engine compatible)
            Button {
                Task { await authManager.login() }
            } label: {
                Label("Sign in with NVIDIA", systemImage: "person.badge.key")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.bordered)
            .tint(.green)

            // Instruction
            VStack(spacing: 8) {
                Image(systemName: "iphone")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Your iPhone will open the NVIDIA sign-in page.\nComplete login there and return to Apple TV.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(80)
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2)
                .tint(.white)
            Text("Signing in…")
                .font(.title2)
                .foregroundStyle(.white)
        }
    }
}
