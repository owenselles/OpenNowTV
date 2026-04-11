// NOTE: This file requires the WebRTC package to be added to the Xcode project via SPM:
//   https://github.com/livekit/webrtc-xcframework
//   Product: WebRTC
//

import Foundation
import LiveKitWebRTC
import Observation

// MARK: - Stream State

enum StreamState: Equatable {
    case idle
    case connecting
    case streaming
    case disconnected(reason: String)
    case failed(message: String)
}

// MARK: - Stream Statistics

struct StreamStats {
    var bitrateKbps: Int = 0
    var resolutionWidth: Int = 0
    var resolutionHeight: Int = 0
    var fps: Double = 0
    var rttMs: Double = 0
    var packetLossPercent: Double = 0
    var jitterMs: Double = 0
    var codec: String = ""
    var gpuType: String = ""
}

// MARK: - GFNStreamController

@Observable
@MainActor
final class GFNStreamController: NSObject {
    private(set) var state: StreamState = .idle
    private(set) var stats = StreamStats()
    private(set) var videoTrack: LKRTCVideoTrack?

    private var peerConnection: LKRTCPeerConnection?
    private var inputDataChannel: LKRTCDataChannel?
    private var signaling: GFNSignalingClient?
    private var inputSender: InputSender?
    private var statsTimer: Timer?
    private var protocolVersion = 2
    private var sessionInfo: SessionInfo?

    private static let factory: LKRTCPeerConnectionFactory = {
        LKRTCInitializeSSL()
        let encoderFactory = LKRTCDefaultVideoEncoderFactory()
        let decoderFactory = LKRTCDefaultVideoDecoderFactory()
        return LKRTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
    }()

    // MARK: Connect

    func connect(session: SessionInfo) async {
        guard state == .idle || state == .disconnected(reason: "") else { return }
        state = .connecting
        sessionInfo = session
        stats.gpuType = session.gpuType ?? ""

        setupSignaling(session: session)
        do {
            try await signaling?.connect()
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    // MARK: Disconnect

    func disconnect() {
        statsTimer?.invalidate()
        inputSender?.stop()
        signaling?.disconnect()
        peerConnection?.close()
        peerConnection = nil
        inputDataChannel = nil
        videoTrack = nil
        state = .idle
    }

    // MARK: Private — Signaling Setup

    private func setupSignaling(session: SessionInfo) {
        let client = GFNSignalingClient(signalingUrl: session.signalingUrl, sessionId: session.sessionId)
        client.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in self?.handleSignalingEvent(event) }
        }
        signaling = client
    }

    private func handleSignalingEvent(_ event: SignalingEvent) {
        switch event {
        case .connected:
            break
        case .offer(let sdp):
            Task { await handleOffer(sdp: sdp) }
        case .remoteICE(let candidate, let sdpMid, let sdpMLineIndex):
            addRemoteICE(candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex)
        case .disconnected(let reason):
            state = .disconnected(reason: reason)
        case .error(let msg):
            state = .failed(message: msg)
        case .log:
            break
        }
    }

    // MARK: Private — WebRTC Peer Connection

    private func handleOffer(sdp: String) async {
        guard let session = sessionInfo else { return }

        let iceServers: [LKRTCIceServer] = session.iceServers.map {
            LKRTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential)
        }
        let config = LKRTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require

        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = GFNStreamController.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            state = .failed(message: "Failed to create LKRTCPeerConnection")
            return
        }
        peerConnection = pc

        // Open input data channel (reliable + ordered)
        let dcConfig = LKRTCDataChannelConfiguration()
        dcConfig.isOrdered = true
        dcConfig.isNegotiated = false
        if let dc = pc.dataChannel(forLabel: "input", configuration: dcConfig) {
            inputDataChannel = dc
            dc.delegate = self
        }

        // Add receive-only video transceiver
        let transceiverInit = LKRTCRtpTransceiverInit()
        transceiverInit.direction = .recvOnly
        pc.addTransceiver(of: .video, init: transceiverInit)

        // Set remote description (the server's offer)
        let remoteSDP = LKRTCSessionDescription(type: .offer, sdp: sdp)
        try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(remoteSDP) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }

        // Create answer
        let answerConstraints = LKRTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveVideo": "true", "OfferToReceiveAudio": "true"],
            optionalConstraints: nil
        )
        do {
            let answer: LKRTCSessionDescription = try await withCheckedThrowingContinuation { cont in
                pc.answer(for: answerConstraints) { sdp, error in
                    if let e = error { cont.resume(throwing: e); return }
                    if let sdp { cont.resume(returning: sdp) } else { cont.resume(throwing: StreamError.noSDP) }
                }
            }
            // Set local description
            try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                pc.setLocalDescription(answer) { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
            signaling?.sendAnswer(sdp: answer.sdp)
        } catch {
            state = .failed(message: "Answer creation failed: \(error.localizedDescription)")
        }
    }

    private func addRemoteICE(candidate: String, sdpMid: String?, sdpMLineIndex: Int?) {
        let ice = LKRTCIceCandidate(
            sdp: candidate,
            sdpMLineIndex: Int32(sdpMLineIndex ?? 0),
            sdpMid: sdpMid
        )
        peerConnection?.add(ice)
    }

    // MARK: Private — Stats

    private func startStatsTimer() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.collectStats()
        }
    }

    private func collectStats() {
        peerConnection?.statistics { [weak self] report in
            Task { @MainActor [weak self] in self?.parseStats(report) }
        }
    }

    private func parseStats(_ report: LKRTCStatisticsReport) {
        for (_, stat) in report.statistics {
            if stat.type == "inbound-rtp", stat.values["kind"] as? String == "video" {
                let bitsPerSecond = stat.values["bytesReceived"] as? Double ?? 0
                stats.bitrateKbps = Int(bitsPerSecond * 8 / 1000)
                stats.fps = stat.values["framesPerSecond"] as? Double ?? 0
                if let w = stat.values["frameWidth"] as? Double,
                   let h = stat.values["frameHeight"] as? Double {
                    stats.resolutionWidth  = Int(w)
                    stats.resolutionHeight = Int(h)
                }
                stats.codec = stat.values["codecId"] as? String ?? ""
                stats.jitterMs = (stat.values["jitter"] as? Double ?? 0) * 1000
            }
            if stat.type == "candidate-pair", stat.values["state"] as? String == "succeeded" {
                stats.rttMs = (stat.values["currentRoundTripTime"] as? Double ?? 0) * 1000
            }
        }
    }
}

// MARK: - LKRTCPeerConnectionDelegate

extension GFNStreamController: LKRTCPeerConnectionDelegate {
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {
        Task { @MainActor [weak self] in
            switch newState {
            case .connected, .completed:
                self?.state = .streaming
                self?.startStatsTimer()
            case .disconnected:
                self?.state = .disconnected(reason: "ICE disconnected")
            case .failed:
                self?.state = .failed(message: "ICE connection failed")
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        Task { @MainActor [weak self] in
            self?.signaling?.sendICECandidate(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: Int(candidate.sdpMLineIndex)
            )
        }
    }

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection,
                                    didAdd rtpReceiver: LKRTCRtpReceiver,
                                    streams mediaStreams: [LKRTCMediaStream]) {
        guard let track = rtpReceiver.track as? LKRTCVideoTrack else { return }
        Task { @MainActor [weak self] in
            self?.videoTrack = track
        }
    }
}

// MARK: - LKRTCDataChannelDelegate

extension GFNStreamController: LKRTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {
        if dataChannel.readyState == .open {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let sender = InputSender(channel: self)
                sender.setProtocolVersion(self.protocolVersion)
                sender.start()
                self.inputSender = sender
            }
        }
    }

    nonisolated func dataChannel(_ dataChannel: LKRTCDataChannel, didReceiveMessageWith buffer: LKRTCDataBuffer) {
        // Parse any incoming protocol version negotiation if present
        if buffer.data.count >= 2 {
            let byte0 = buffer.data[0]
            let byte1 = buffer.data[1]
            if byte0 == 0x01 { // hypothetical version negotiation byte
                Task { @MainActor [weak self] in
                    self?.protocolVersion = Int(byte1)
                    self?.inputSender?.setProtocolVersion(Int(byte1))
                }
            }
        }
    }
}

// MARK: - DataChannelSender conformance

extension GFNStreamController: DataChannelSender {
    nonisolated func sendData(_ data: Data) {
        // Access inputDataChannel on the main actor asynchronously to satisfy isolation
        Task { @MainActor [weak self] in
            guard let dc = self?.inputDataChannel, dc.readyState == .open else { return }
            let buffer = LKRTCDataBuffer(data: data, isBinary: true)
            dc.sendData(buffer)
        }
    }
}

// MARK: - Errors

enum StreamError: Error {
    case noSDP
}
