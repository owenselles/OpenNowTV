import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) var authManager
    @Environment(GamesViewModel.self) var viewModel

    private let resolutions = ["1280x720", "1920x1080", "3840x2160"]
    private let fpsOptions = [30, 60, 120]

    var body: some View {
        @Bindable var vm = viewModel

        NavigationStack {
            Form {
                Section("Stream Quality") {
                    Picker("Resolution", selection: $vm.streamSettings.resolution) {
                        ForEach(resolutions, id: \.self) { res in
                            Text(res).tag(res)
                        }
                    }

                    Picker("Frame Rate", selection: $vm.streamSettings.fps) {
                        ForEach(fpsOptions, id: \.self) { fps in
                            Text("\(fps) fps").tag(fps)
                        }
                    }

                    Picker("Codec", selection: $vm.streamSettings.codec) {
                        ForEach(VideoCodec.allCases, id: \.self) { codec in
                            Text(codec.rawValue).tag(codec)
                        }
                    }

                    Picker("Color Quality", selection: $vm.streamSettings.colorQuality) {
                        ForEach(ColorQuality.allCases, id: \.self) { q in
                            Text(colorQualityLabel(q)).tag(q)
                        }
                    }
                }

                Section("Controller") {
                    LabeledContent("Deadzone", value: "15% (default)")
                    LabeledContent("Protocol", value: "XInput v2/v3")
                }

                Section("Account") {
                    if let user = authManager.session?.user {
                        LabeledContent("Name", value: user.displayName)
                        if let email = user.email {
                            LabeledContent("Email", value: email)
                        }
                        LabeledContent("Membership", value: user.membershipTier)
                    }

                    Button(role: .destructive) {
                        authManager.logout()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func colorQualityLabel(_ q: ColorQuality) -> String {
        switch q {
        case .sdr8bit: return "SDR 8-bit"
        case .sdr10bit: return "SDR 10-bit"
        case .hdr10bit: return "HDR 10-bit"
        }
    }
}
