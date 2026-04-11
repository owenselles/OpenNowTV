// NOTE: Requires WebRTC SPM package (https://github.com/livekit/webrtc-xcframework)

import AVFoundation
import UIKit
import LiveKitWebRTC

// MARK: - VideoSurfaceView

/// Full-screen hardware-accelerated video renderer.
/// Wraps LKRTCMTLVideoView (Metal-backed) for best performance on Apple TV.
/// Falls back to AVSampleBufferDisplayLayer if needed.
final class VideoSurfaceView: UIView {
    private let rtcView = LKRTCMTLVideoView(frame: .zero)

    var videoTrack: LKRTCVideoTrack? {
        didSet {
            oldValue?.remove(rtcView)
            videoTrack?.add(rtcView)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .black
        rtcView.translatesAutoresizingMaskIntoConstraints = false
        rtcView.videoContentMode = .scaleAspectFill
        addSubview(rtcView)
        NSLayoutConstraint.activate([
            rtcView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rtcView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rtcView.topAnchor.constraint(equalTo: topAnchor),
            rtcView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

// MARK: - SwiftUI Wrapper

import SwiftUI

struct VideoSurfaceViewRepresentable: UIViewRepresentable {
    let streamController: GFNStreamController

    func makeUIView(context: Context) -> VideoSurfaceView {
        VideoSurfaceView()
    }

    func updateUIView(_ uiView: VideoSurfaceView, context: Context) {
        uiView.videoTrack = streamController.videoTrack
    }
}
