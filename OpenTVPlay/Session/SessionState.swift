import Foundation

// MARK: - Stream Settings

struct StreamSettings: Codable, Equatable {
    var resolution: String = "1920x1080"
    var fps: Int = 60
    var maxBitrateKbps: Int = 50_000
    var codec: VideoCodec = .h265
    var colorQuality: ColorQuality = .sdr8bit
    var keyboardLayout: String = "en-US"
    var gameLanguage: String = "en_US"
    var enableL4S: Bool = false
}

enum VideoCodec: String, Codable, CaseIterable {
    case h264 = "H264"
    case h265 = "H265"
    case av1  = "AV1"
}

enum ColorQuality: String, Codable, CaseIterable {
    case sdr8bit  = "SDR8bit"
    case sdr10bit = "SDR10bit"
    case hdr10bit = "HDR10bit"

    var bitDepth: Int { self == .sdr8bit ? 8 : 10 }
    var chromaFormat: Int { self == .hdr10bit ? 2 : 1 }
}

// MARK: - ICE Server

struct IceServer: Codable {
    let urls: [String]
    let username: String?
    let credential: String?
}

// MARK: - Session Info (returned by CloudMatch)

struct SessionInfo {
    let sessionId: String
    let status: Int
    let zone: String
    let streamingBaseUrl: String
    let serverIp: String
    let signalingServer: String
    let signalingUrl: String
    let gpuType: String?
    let iceServers: [IceServer]
    let mediaConnectionInfo: MediaConnectionInfo?
    let clientId: String
    let deviceId: String
}

struct MediaConnectionInfo {
    let ip: String
    let port: Int
}

// MARK: - Active Session Info

struct ActiveSessionInfo: Decodable {
    let sessionId: String
    let status: Int
    let appId: String?
}

// MARK: - Games

struct GameInfo: Identifiable {
    let id: String
    let title: String
    let boxArtUrl: String?
    let heroBannerUrl: String?
    var isInLibrary: Bool
    var variants: [GameVariant]
}

struct GameVariant {
    let id: String
    let appStore: String
    var appId: String?
}

// MARK: - Session Create Request

struct SessionCreateRequest {
    let appId: String
    let internalTitle: String?
    let token: String
    let zone: String
    let streamingBaseUrl: String?
    let settings: StreamSettings
    let accountLinked: Bool
}
