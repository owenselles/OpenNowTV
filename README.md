# OpenNowTV

A native GeForce NOW client for Apple TV. Stream your entire PC game library directly on tvOS with full controller support — no browser, no workarounds.

> **Personal use / sideload only.** This project is not affiliated with or endorsed by NVIDIA.

---

## Features

- **Native tvOS UI** — Focus-engine compatible game browser, navigable entirely by remote or controller
- **Full GFN streaming** — WebRTC-based, H.264/H.265, up to 4K@60fps (subject to your GFN subscription)
- **Controller support** — Up to 4 simultaneous MFi/Xbox/PlayStation controllers via GameController framework
- **NVIDIA OAuth login** — Standard PKCE flow; authentication completes on your paired iPhone via Handoff
- **Live stats overlay** — Bitrate, resolution, FPS, RTT, packet loss — toggle with the Menu button
- **Keychain persistence** — Session tokens stored securely, auto-refreshed on launch

## Requirements

- Apple TV (4K, 2nd generation or later)
- Xcode 16+ on a Mac
- Active GeForce NOW account (Free, Priority, or Ultimate)
- Apple Developer account (free tier works for sideloading)
- iPhone paired with the Apple TV (for initial login via Handoff)

## Getting Started

### 1. Clone

```bash
git clone https://github.com/your-username/OpenTVPlay.git
cd OpenTVPlay
```

### 2. Open in Xcode

```bash
open OpenTVPlay.xcodeproj
```

The `LiveKitWebRTC` package resolves automatically via Swift Package Manager.

### 3. Set your Team

In Xcode → OpenTVPlay target → Signing & Capabilities, select your Apple Developer team. Automatic signing will create the provisioning profile.

### 4. Build & Run

Connect your Apple TV via USB-C or select it as the run destination over the network, then hit **Run** (⌘R).

On first launch, the app will prompt you to sign in. A notification appears on your paired iPhone — tap it to complete login in Safari, then return to the TV.

---

## Architecture

```
OpenTVPlay/
├── Auth/
│   ├── AuthManager.swift        @Observable auth state, Keychain persistence
│   └── NVIDIAAuthAPI.swift      OAuth 2.0 PKCE, token refresh, user info
├── Session/
│   ├── SessionState.swift       Models: GameInfo, SessionInfo, StreamSettings
│   ├── CloudMatchClient.swift   Session create/poll/stop (NVIDIA CloudMatch API)
│   └── GamesClient.swift        Game library via GraphQL persisted query
├── Streaming/
│   ├── GFNStreamController.swift  WebRTC peer connection lifecycle (@Observable)
│   ├── SignalingClient.swift       WebSocket signaling (SDP offer/answer, ICE)
│   └── InputSender.swift          GCController → XInput binary protocol
├── Video/
│   └── VideoSurfaceView.swift     LKRTCMTLVideoView (Metal) as UIViewRepresentable
└── UI/
    ├── LoginView.swift            Sign-in screen with Handoff instructions
    ├── LibraryView.swift          LazyVGrid game browser
    └── StreamView.swift           Full-screen player + HUD overlay
```

### Protocol

The GFN streaming protocol was reverse-engineered by [OpenNOW](https://github.com/OpenCloudGaming/OpenNOW) (TypeScript/Electron). This project ports their work to native Swift.

| Layer | Implementation |
|-------|---------------|
| Auth | OAuth 2.0 PKCE → `login.nvidia.com` |
| Session | REST → CloudMatch (`cloudmatchbeta.nvidiagrid.net`) |
| Signaling | WebSocket (`/nvst/sign_in`) — SDP offer/answer + ICE |
| Streaming | WebRTC via [livekit/webrtc-xcframework](https://github.com/livekit/webrtc-xcframework) |
| Input | XInput binary protocol over WebRTC data channel |
| Game catalog | GraphQL persisted query → `games.geforce.com` |

---

## Known Limitations

- **No App Store.** NVIDIA has not published a public API for third-party GFN clients. This project is for personal sideloading only.
- **SDP munging not yet implemented.** The GFN server sends a non-standard SDP with proprietary extensions (`a=ri.*`). Advanced codec negotiation (AV1, partial reliability) from OpenNOW's `sdp.ts` is not yet ported.
- **No microphone support.** The server supports mic input over a second data channel; this is not implemented yet.
- **No queue/ad handling.** During high-demand periods, GFN places sessions in a queue and shows ads while waiting. This app shows a spinner only.

## Contributing

PRs welcome, especially for:
- SDP munging (`Streaming/SDPProcessor.swift`)
- Microphone support
- Session queue / ad state UI
- macOS Catalyst or visionOS port

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

- [OpenNOW](https://github.com/OpenCloudGaming/OpenNOW) — GFN protocol reverse engineering
- [livekit/webrtc-xcframework](https://github.com/livekit/webrtc-xcframework) — WebRTC for Apple platforms
