import SwiftUI
import AVFoundation
import UIKit

/// UIViewRepresentable hosting the live AVCaptureVideoPreviewLayer.
public struct CameraPreviewView: UIViewRepresentable {
    public let session: AVCaptureSession
    public let isSimulator: Bool

    public init(session: AVCaptureSession, isSimulator: Bool = false) {
        self.session = session
        self.isSimulator = isSimulator
    }

    public func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        if !isSimulator {
            view.videoPreviewLayer.session = session
            view.videoPreviewLayer.videoGravity = .resizeAspectFill
        }
        return view
    }

    public func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if !isSimulator && uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }
}

public final class CameraPreviewUIView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

