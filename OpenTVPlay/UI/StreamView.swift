import SwiftUI

struct StreamView: View {
    let game: GameInfo
    var settings: StreamSettings = StreamSettings()
    let onDismiss: () -> Void

    @Environment(AuthManager.self) var authManager
    @State private var streamController = GFNStreamController()
    @State private var showOverlay = false
    @State private var overlayTimer: Timer?

    private let cloudMatchClient = CloudMatchClient()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch streamController.state {
            case .idle, .connecting:
                connectingView
            case .streaming:
                streamingView
            case .disconnected(let reason):
                disconnectedView(reason)
            case .failed(let message):
                failedView(message)
            }
        }
        .ignoresSafeArea()
        .task { await startSession() }
        .onDisappear { streamController.disconnect() }
        // Menu button toggles the HUD overlay
        .onExitCommand {
            if streamController.state == .streaming {
                toggleOverlay()
            } else {
                disconnect()
            }
        }
    }

    // MARK: Connecting

    private var connectingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2)
                .tint(.white)
            Text("Starting \(game.title)…")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Connecting to a GeForce NOW server")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Streaming

    private var streamingView: some View {
        ZStack {
            VideoSurfaceViewRepresentable(streamController: streamController)
                .ignoresSafeArea()

            if showOverlay {
                statsOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showOverlay)
    }

    // MARK: Stats Overlay

    private var statsOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(streamController.stats.resolutionWidth)×\(streamController.stats.resolutionHeight) @ \(Int(streamController.stats.fps))fps", systemImage: "tv")
            Label("\(streamController.stats.bitrateKbps / 1000) Mbps", systemImage: "wifi")
            Label("RTT \(Int(streamController.stats.rttMs)) ms", systemImage: "network")
            Label("Loss \(String(format: "%.1f", streamController.stats.packetLossPercent))%", systemImage: "arrow.triangle.2.circlepath")
            if !streamController.stats.gpuType.isEmpty {
                Label(streamController.stats.gpuType, systemImage: "cpu")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(40)
    }

    // MARK: Disconnected / Failed

    private func disconnectedView(_ reason: String) -> some View {
        statusView(
            icon: "wifi.slash",
            title: "Disconnected",
            message: reason,
            color: .yellow
        )
    }

    private func failedView(_ message: String) -> some View {
        statusView(
            icon: "exclamationmark.triangle",
            title: "Stream Failed",
            message: message,
            color: .red
        )
    }

    private func statusView(icon: String, title: String, message: String, color: Color) -> some View {
        VStack(spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(color)
            Text(title)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 24) {
                Button("Retry") { Task { await startSession() } }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                Button("Exit") { disconnect() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .padding(60)
    }

    // MARK: Actions

    private func startSession() async {
        do {
            let token = try await authManager.resolveToken()
            let provider = authManager.session?.provider
            let streamingBaseUrl = provider?.streamingServiceUrl ?? NVIDIAAuth.defaultStreamingUrl
            let base = streamingBaseUrl.hasSuffix("/") ? String(streamingBaseUrl.dropLast()) : streamingBaseUrl

            guard let appId = game.variants.first?.appId ?? game.variants.first?.id else { return }

            let request = SessionCreateRequest(
                appId: appId,
                internalTitle: game.title,
                token: token,
                zone: "",
                streamingBaseUrl: base,
                settings: settings,
                accountLinked: true
            )

            var sessionInfo = try await cloudMatchClient.createSession(request)

            // Poll until status == 2 (ready) or 3 (streaming)
            var attempts = 0
            while sessionInfo.status != 2 && sessionInfo.status != 3 && attempts < 60 {
                try await Task.sleep(for: .seconds(2))
                sessionInfo = try await cloudMatchClient.pollSession(
                    sessionId: sessionInfo.sessionId,
                    token: token,
                    base: sessionInfo.streamingBaseUrl,
                    serverIp: sessionInfo.serverIp.isEmpty ? nil : sessionInfo.serverIp,
                    clientId: sessionInfo.clientId,
                    deviceId: sessionInfo.deviceId
                )
                attempts += 1
            }

            await streamController.connect(session: sessionInfo)
        } catch {
            // error will propagate to streamController.state via connect()
        }
    }

    private func disconnect() {
        streamController.disconnect()
        onDismiss()
    }

    private func toggleOverlay() {
        overlayTimer?.invalidate()
        showOverlay.toggle()
        if showOverlay {
            overlayTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                withAnimation { showOverlay = false }
            }
        }
    }
}
