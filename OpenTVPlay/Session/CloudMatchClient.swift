import Foundation

// MARK: - CloudMatch Headers

private func gfnHeaders(token: String, clientId: String, deviceId: String, includeOrigin: Bool = true) -> [String: String] {
    var h: [String: String] = [
        "User-Agent": NVIDIAAuth.userAgent,
        "Authorization": "GFNJWT \(token)",
        "Content-Type": "application/json",
        "nv-browser-type": "CHROME",
        "nv-client-id": clientId,
        "nv-client-streamer": "NVIDIA-CLASSIC",
        "nv-client-type": "NATIVE",
        "nv-client-version": "2.0.80.173",
        "nv-device-make": "UNKNOWN",
        "nv-device-model": "UNKNOWN",
        "nv-device-os": "MACOS",
        "nv-device-type": "DESKTOP",
        "x-device-id": deviceId,
    ]
    if includeOrigin {
        h["Origin"] = "https://play.geforcenow.com"
        h["Referer"] = "https://play.geforcenow.com/"
    }
    return h
}

// MARK: - CloudMatch Response Types

private struct CloudMatchResponse: Decodable {
    let session: SessionPayload
    struct SessionPayload: Decodable {
        let sessionId: String
        let status: Int
        let gpuType: String?
        let queuePosition: Int?
        let connectionInfo: [ConnectionInfo]?
        let iceServerConfiguration: IceServerConfig?
        let sessionControlInfo: SessionControlInfo?

        struct ConnectionInfo: Decodable {
            let usage: Int
            let ip: AnyCodableString?
            let port: Int
            let resourcePath: String?
        }

        struct IceServerConfig: Decodable {
            let iceServers: [RawIceServer]?
            struct RawIceServer: Decodable {
                let urls: AnyCodableStringArray
                let username: String?
                let credential: String?
            }
        }

        struct SessionControlInfo: Decodable {
            let ip: AnyCodableString?
        }
    }
}

// GFN API returns ip as either a string or array of strings
private struct AnyCodableString: Decodable {
    let value: String?
    init(from decoder: Decoder) throws {
        if let arr = try? [String].init(from: decoder) {
            value = arr.first
        } else {
            value = try? String(from: decoder)
        }
    }
}

private struct AnyCodableStringArray: Decodable {
    let values: [String]
    init(from decoder: Decoder) throws {
        if let arr = try? [String].init(from: decoder) {
            values = arr
        } else if let single = try? String(from: decoder) {
            values = [single]
        } else {
            values = []
        }
    }
}

private struct GetSessionsResponse: Decodable {
    let requestStatus: RequestStatus
    let sessions: [SessionEntry]?
    struct RequestStatus: Decodable {
        let statusCode: Int
        let statusDescription: String?
    }
    struct SessionEntry: Decodable {
        let sessionId: String
        let status: Int
        let appId: String?
    }
}

// MARK: - Session Request Body

private func buildSessionRequestBody(_ input: SessionCreateRequest) -> [String: Any] {
    let resolutionParts = input.settings.resolution.split(separator: "x")
    let width = Int(resolutionParts.first ?? "1920") ?? 1920
    let height = Int(resolutionParts.last ?? "1080") ?? 1080
    let tzOffset = -TimeZone.current.secondsFromGMT() * 1000

    return [
        "sessionRequestData": [
            "appId": input.appId,
            "internalTitle": input.internalTitle as Any,
            "availableSupportedControllers": [],
            "networkTestSessionId": NSNull(),
            "parentSessionId": NSNull(),
            "clientIdentification": "GFN-PC",
            "deviceHashId": UUID().uuidString,
            "clientVersion": "30.0",
            "sdkVersion": "1.0",
            "streamerVersion": 1,
            "clientPlatformName": "windows",
            "clientRequestMonitorSettings": [[
                "widthInPixels": width,
                "heightInPixels": height,
                "framesPerSecond": input.settings.fps,
                "sdrHdrMode": 0,
                "displayData": [
                    "desiredContentMaxLuminance": 0,
                    "desiredContentMinLuminance": 0,
                    "desiredContentMaxFrameAverageLuminance": 0,
                ],
                "dpi": 100,
            ]],
            "useOps": true,
            "audioMode": 2,
            "metaData": [
                ["key": "SubSessionId", "value": UUID().uuidString],
                ["key": "wssignaling", "value": "1"],
                ["key": "GSStreamerType", "value": "WebRTC"],
                ["key": "networkType", "value": "Unknown"],
                ["key": "ClientImeSupport", "value": "0"],
                ["key": "clientPhysicalResolution", "value": "{\"horizontalPixels\":\(width),\"verticalPixels\":\(height)}"],
                ["key": "surroundAudioInfo", "value": "2"],
            ],
            "sdrHdrMode": 0,
            "clientDisplayHdrCapabilities": NSNull(),
            "surroundAudioInfo": 0,
            "remoteControllersBitmap": 0,
            "clientTimezoneOffset": tzOffset,
            "enhancedStreamMode": 1,
            "appLaunchMode": 1,
            "secureRTSPSupported": false,
            "partnerCustomData": "",
            "accountLinked": input.accountLinked,
            "enablePersistingInGameSettings": true,
            "userAge": 26,
            "requestedStreamingFeatures": [
                "reflex": input.settings.fps >= 120,
                "bitDepth": input.settings.colorQuality.bitDepth,
                "cloudGsync": false,
                "enabledL4S": input.settings.enableL4S,
                "mouseMovementFlags": 0,
                "trueHdr": false,
                "supportedHidDevices": 0,
                "profile": 0,
                "fallbackToLogicalResolution": false,
                "hidDevices": NSNull(),
                "chromaFormat": input.settings.colorQuality.chromaFormat,
                "prefilterMode": 0,
                "prefilterSharpness": 0,
                "prefilterNoiseReduction": 0,
                "hudStreamingMode": 0,
                "sdrColorSpace": 2,
                "hdrColorSpace": 0,
            ],
        ],
    ]
}

// MARK: - Signaling URL Resolution

private func resolveSignalingUrl(serverIp: String, resourcePath: String) -> String {
    if resourcePath.hasPrefix("rtsps://") || resourcePath.hasPrefix("rtsp://") {
        let withoutScheme = resourcePath.hasPrefix("rtsps://")
            ? String(resourcePath.dropFirst("rtsps://".count))
            : String(resourcePath.dropFirst("rtsp://".count))
        let host = withoutScheme.components(separatedBy: ":").first?
                                .components(separatedBy: "/").first ?? ""
        if !host.isEmpty && !host.hasPrefix(".") {
            return "wss://\(host)/nvst/"
        }
    }
    if resourcePath.hasPrefix("wss://") { return resourcePath }
    if resourcePath.hasPrefix("/") { return "wss://\(serverIp):443\(resourcePath)" }
    return "wss://\(serverIp):443/nvst/"
}

// MARK: - CloudMatchClient

actor CloudMatchClient {
    private let urlSession = URLSession.shared

    // MARK: Create Session

    func createSession(_ input: SessionCreateRequest) async throws -> SessionInfo {
        let clientId = UUID().uuidString
        let deviceId = UUID().uuidString
        let base = input.streamingBaseUrl.map {
            $0.hasSuffix("/") ? String($0.dropLast()) : $0
        } ?? "https://prod.cloudmatchbeta.nvidiagrid.net"

        let params = URLComponents(string: "\(base)/v2/session")!.url!
            .appending(queryItems: [
                URLQueryItem(name: "keyboardLayout", value: input.settings.keyboardLayout),
                URLQueryItem(name: "languageCode", value: input.settings.gameLanguage),
            ])

        let body = buildSessionRequestBody(input)
        var request = URLRequest(url: params)
        request.httpMethod = "POST"
        for (k, v) in gfnHeaders(token: input.token, clientId: clientId, deviceId: deviceId, includeOrigin: true) {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await urlSession.data(for: request)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw CloudMatchError.sessionCreateFailed(msg)
        }
        let payload = try JSONDecoder().decode(CloudMatchResponse.self, from: data)
        return try toSessionInfo(base: base, payload: payload, clientId: clientId, deviceId: deviceId)
    }

    // MARK: Poll Session

    func pollSession(sessionId: String, token: String, base: String, serverIp: String?,
                     clientId: String, deviceId: String) async throws -> SessionInfo {
        let effectiveBase = serverIp.map { "https://\($0)" } ?? base
        let url = URL(string: "\(effectiveBase)/v2/session/\(sessionId)")!
        var request = URLRequest(url: url)
        for (k, v) in gfnHeaders(token: token, clientId: clientId, deviceId: deviceId, includeOrigin: false) {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let (data, _) = try await urlSession.data(for: request)
        let payload = try JSONDecoder().decode(CloudMatchResponse.self, from: data)
        return try toSessionInfo(base: effectiveBase, payload: payload, clientId: clientId, deviceId: deviceId)
    }

    // MARK: Stop Session

    func stopSession(sessionId: String, token: String, base: String) async throws {
        let url = URL(string: "\(base)/v2/session/\(sessionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("GFNJWT \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(NVIDIAAuth.userAgent, forHTTPHeaderField: "User-Agent")
        _ = try await urlSession.data(for: request)
    }

    // MARK: Active Sessions

    func getActiveSessions(token: String, base: String) async throws -> [ActiveSessionInfo] {
        let url = URL(string: "\(base)/v2/sessions")!
        var request = URLRequest(url: url)
        request.setValue("GFNJWT \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(NVIDIAAuth.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await urlSession.data(for: request)
        let resp = try JSONDecoder().decode(GetSessionsResponse.self, from: data)
        return (resp.sessions ?? []).filter { $0.status == 2 || $0.status == 3 }.map {
            ActiveSessionInfo(sessionId: $0.sessionId, status: $0.status, appId: $0.appId)
        }
    }

    // MARK: Private

    private func toSessionInfo(base: String, payload: CloudMatchResponse, clientId: String, deviceId: String) throws -> SessionInfo {
        let s = payload.session
        let connections = s.connectionInfo ?? []

        // Signaling server: usage=14
        let sigConn = connections.first { $0.usage == 14 && $0.ip?.value != nil }
                   ?? connections.first { $0.ip?.value != nil }
        let serverIp = sigConn?.ip?.value ?? s.sessionControlInfo?.ip?.value ?? ""
        let resourcePath = sigConn?.resourcePath ?? "/nvst/"
        let signalingUrl = resolveSignalingUrl(serverIp: serverIp, resourcePath: resourcePath)

        // ICE servers
        let rawIceServers = s.iceServerConfiguration?.iceServers ?? []
        let iceServers = rawIceServers.isEmpty
            ? defaultIceServers()
            : rawIceServers.map { IceServer(urls: $0.urls.values, username: $0.username, credential: $0.credential) }

        // Media connection
        let mediaConn = connections.first { $0.usage == 2 }
                     ?? connections.first { $0.usage == 17 }
        let media = mediaConn.flatMap { mc -> MediaConnectionInfo? in
            guard let ip = mc.ip?.value, mc.port > 0 else { return nil }
            return MediaConnectionInfo(ip: ip, port: mc.port)
        }

        return SessionInfo(
            sessionId: s.sessionId,
            status: s.status,
            zone: "",
            streamingBaseUrl: base,
            serverIp: serverIp,
            signalingServer: serverIp.contains(":") ? serverIp : "\(serverIp):443",
            signalingUrl: signalingUrl,
            gpuType: s.gpuType,
            iceServers: iceServers,
            mediaConnectionInfo: media,
            clientId: clientId,
            deviceId: deviceId
        )
    }

    private func defaultIceServers() -> [IceServer] {
        [
            IceServer(urls: ["stun:s1.stun.gamestream.nvidia.com:19308"], username: nil, credential: nil),
            IceServer(urls: ["stun:stun.l.google.com:19302"], username: nil, credential: nil),
        ]
    }
}

// MARK: - Errors

enum CloudMatchError: Error, LocalizedError {
    case sessionCreateFailed(String)
    case missingServerIp

    var errorDescription: String? {
        switch self {
        case .sessionCreateFailed(let msg): return "Session creation failed: \(msg)"
        case .missingServerIp: return "CloudMatch response missing server IP."
        }
    }
}
