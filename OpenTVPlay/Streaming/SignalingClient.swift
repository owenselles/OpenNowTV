import Foundation

// MARK: - Signaling Events

enum SignalingEvent {
    case connected
    case disconnected(reason: String)
    case offer(sdp: String)
    case remoteICE(candidate: String, sdpMid: String?, sdpMLineIndex: Int?)
    case log(String)
    case error(String)
}

// MARK: - GFN Signaling Client

/// WebSocket-based signaling for GeForce NOW WebRTC sessions.
/// Protocol: wss://{server}/nvst/sign_in?peer_id={name}&version=2
/// WebSocket protocol header: x-nv-sessionid.{sessionId}
final class GFNSignalingClient: NSObject {
    private let signalingUrl: String
    private let sessionId: String

    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var ackCounter = 0
    private let peerId = 2
    private let peerName: String

    var onEvent: ((SignalingEvent) -> Void)?

    init(signalingUrl: String, sessionId: String) {
        self.signalingUrl = signalingUrl
        self.sessionId = sessionId
        self.peerName = "peer-\(Int.random(in: 0..<10_000_000_000))"
    }

    // MARK: Connect

    func connect() async throws {
        guard let baseUrl = URL(string: signalingUrl) else {
            throw SignalingError.invalidUrl(signalingUrl)
        }
        var comps = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false)!
        comps.path = (comps.path.hasSuffix("/") ? comps.path : comps.path + "/") + "sign_in"
        comps.queryItems = [
            URLQueryItem(name: "peer_id", value: peerName),
            URLQueryItem(name: "version", value: "2"),
        ]
        let url = comps.url!

        var request = URLRequest(url: url)
        // GFN signaling server requires the session ID in the Sec-WebSocket-Protocol header
        request.setValue("x-nv-sessionid.\(sessionId)", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.setValue("https://play.geforcenow.com", forHTTPHeaderField: "Origin")
        request.setValue(NVIDIAAuth.userAgent, forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        // Send peer_info immediately after connecting
        sendPeerInfo()
        startHeartbeat()
        startReceiving()
        onEvent?(.connected)
    }

    // MARK: Send Answer

    func sendAnswer(sdp: String, nvstSdp: String? = nil) {
        var payload: [String: Any] = ["type": "answer", "sdp": sdp]
        if let nvstSdp { payload["nvstSdp"] = nvstSdp }
        let msg: [String: Any] = [
            "peer_msg": ["from": peerId, "to": 1, "msg": jsonString(payload)],
            "ackid": nextAckId(),
        ]
        sendJson(msg)
    }

    // MARK: Send ICE Candidate

    func sendICECandidate(candidate: String, sdpMid: String?, sdpMLineIndex: Int?) {
        var payload: [String: Any] = ["candidate": candidate]
        if let sdpMid { payload["sdpMid"] = sdpMid }
        if let sdpMLineIndex { payload["sdpMLineIndex"] = sdpMLineIndex }
        let msg: [String: Any] = [
            "peer_msg": ["from": peerId, "to": 1, "msg": jsonString(payload)],
            "ackid": nextAckId(),
        ]
        sendJson(msg)
    }

    // MARK: Request Keyframe

    func requestKeyframe(reason: String = "decoder_recovery", backlogFrames: Int = 0, attempt: Int = 1) {
        let payload: [String: Any] = [
            "type": "request_keyframe",
            "reason": reason,
            "backlogFrames": backlogFrames,
            "attempt": attempt,
        ]
        sendJson(["peer_msg": ["from": peerId, "to": 1, "msg": jsonString(payload)], "ackid": nextAckId()])
    }

    // MARK: Disconnect

    func disconnect() {
        heartbeatTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    // MARK: Private

    private func sendPeerInfo() {
        let msg: [String: Any] = [
            "ackid": nextAckId(),
            "peer_info": [
                "browser": "Chrome",
                "browserVersion": "131",
                "connected": true,
                "id": peerId,
                "name": peerName,
                "peerRole": 0,
                "resolution": "1920x1080",
                "version": 2,
            ],
        ]
        sendJson(msg)
    }

    private func startHeartbeat() {
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                sendJson(["hb": 1])
            }
        }
    }

    private func startReceiving() {
        Task { [weak self] in
            guard let self else { return }
            while let task = self.webSocketTask {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text): self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default: break
                    }
                } catch {
                    self.onEvent?(.disconnected(reason: error.localizedDescription))
                    return
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // ACK
        if let ackId = obj["ackid"] as? Int {
            let shouldAck = (obj["peer_info"] as? [String: Any])?["id"] as? Int != peerId
            if shouldAck { sendJson(["ack": ackId]) }
        }

        // Heartbeat
        if obj["hb"] != nil {
            sendJson(["hb": 1])
            return
        }

        // Peer message
        guard let peerMsg = obj["peer_msg"] as? [String: Any],
              let msgStr = peerMsg["msg"] as? String,
              let msgData = msgStr.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any]
        else { return }

        // SDP offer
        if payload["type"] as? String == "offer", let sdp = payload["sdp"] as? String {
            onEvent?(.offer(sdp: sdp))
            return
        }

        // ICE candidate
        if let candidate = payload["candidate"] as? String {
            let mid = payload["sdpMid"] as? String
            let mLineIndex = payload["sdpMLineIndex"] as? Int
            onEvent?(.remoteICE(candidate: candidate, sdpMid: mid, sdpMLineIndex: mLineIndex))
            return
        }

        onEvent?(.log("Unhandled peer message keys: \(payload.keys.joined(separator: ", "))"))
    }

    private func sendJson(_ obj: [String: Any]) {
        guard let task = webSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(text)) { _ in }
    }

    private func jsonString(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        return str
    }

    private func nextAckId() -> Int {
        ackCounter += 1
        return ackCounter
    }
}

extension GFNSignalingClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        heartbeatTask?.cancel()
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "socket closed"
        onEvent?(.disconnected(reason: reasonStr))
    }
}

// MARK: - Errors

enum SignalingError: Error {
    case invalidUrl(String)
}
