import SwiftUI
import AVFoundation

// MARK: - Camera Preview (layerClass тәсілі — ең сенімді)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let isActive: Bool

    func makeUIView(context: Context) -> CameraLayerView {
        let view = CameraLayerView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraLayerView, context: Context) {
        // Session байланысын жаңарт
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }

        // Connection-ды қос/өшір
        uiView.videoPreviewLayer.connection?.isEnabled = isActive
    }
}

// MARK: - Preview UIView (layer = AVCaptureVideoPreviewLayer)

final class CameraLayerView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // bounds пайдалан — landscape/portrait кезінде автоматты жаңарады
        videoPreviewLayer.frame = bounds
        updateVideoOrientation()
    }

    private func updateVideoOrientation() {
        guard let connection = videoPreviewLayer.connection,
              connection.isVideoOrientationSupported else { return }
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            switch scene.interfaceOrientation {
            case .landscapeLeft:      connection.videoOrientation = .landscapeLeft
            case .landscapeRight:     connection.videoOrientation = .landscapeRight
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            default:                  connection.videoOrientation = .portrait
            }
        } else {
            connection.videoOrientation = .portrait
        }
    }
}
