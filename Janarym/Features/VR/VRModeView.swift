import SwiftUI
import AVFoundation
import CoreMotion

// MARK: - Gyroscope Manager

final class GyroManager: ObservableObject {
    private let motion = CMMotionManager()
    @Published var pitch: Double = 0
    @Published var yaw: Double = 0
    @Published var roll: Double = 0

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data, let self else { return }
            self.pitch = data.attitude.pitch
            self.yaw   = data.attitude.yaw
            self.roll  = data.attitude.roll
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}

// MARK: - VR Camera (layerClass — VR үшін view bounds-ке автоматты сыйғызу)

struct VRCameraView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> VRCamUIView {
        let v = VRCamUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: VRCamUIView, context: Context) {}

    class VRCamUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateVideoOrientation()
        }

        private func updateVideoOrientation() {
            guard let connection = previewLayer.connection,
                  connection.isVideoOrientationSupported else { return }
            let videoOrientation: AVCaptureVideoOrientation
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                switch scene.interfaceOrientation {
                case .landscapeLeft:      videoOrientation = .landscapeLeft
                case .landscapeRight:     videoOrientation = .landscapeRight
                case .portraitUpsideDown: videoOrientation = .portraitUpsideDown
                default:                  videoOrientation = .portrait
                }
            } else {
                videoOrientation = .portrait
            }
            connection.videoOrientation = videoOrientation
        }
    }
}

// MARK: - VR Reticle

struct VRReticle: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.5), lineWidth: 1.2)
                .frame(width: 32, height: 32)
            Circle()
                .fill(.white.opacity(isActive ? 0.9 : 0.35))
                .frame(width: 5, height: 5)
        }
    }
}

// MARK: - VR HUD (per eye)

struct VRHUD: View {
    let mode: String
    let isListening: Bool
    let statusText: String

    var body: some View {
        ZStack {
            VStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isListening ? Color.green : .white.opacity(0.4))
                        .frame(width: 5, height: 5)
                    Text(mode)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.35)))
                .padding(.top, 14)

                Spacer()

                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.35)))
                        .padding(.bottom, 10)
                }
            }

            VRReticle(isActive: isListening)
        }
    }
}

// MARK: - Single Eye View (with lens-shaped viewport)

struct VREyeView: View {
    let session: AVCaptureSession
    @ObservedObject var gyro: GyroManager
    let isListening: Bool
    let statusText: String

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Camera with gyro parallax
                VRCameraView(session: session)
                    .frame(width: geo.size.width + 40, height: geo.size.height + 30)
                    .offset(
                        x: CGFloat(gyro.yaw * 15).clamped(to: -25...25),
                        y: CGFloat(-gyro.pitch * 15).clamped(to: -18...18)
                    )
                    .animation(.interpolatingSpring(stiffness: 100, damping: 16), value: gyro.yaw)
                    .animation(.interpolatingSpring(stiffness: 100, damping: 16), value: gyro.pitch)

                // Vignette — VR линза жиегінің қараңғылануы
                RadialGradient(
                    colors: [.clear, .clear, .black.opacity(0.4), .black.opacity(0.85)],
                    center: .center,
                    startRadius: geo.size.width * 0.15,
                    endRadius: geo.size.width * 0.55
                )
                .allowsHitTesting(false)

                // HUD overlay
                VRHUD(mode: "Жалпы", isListening: isListening, statusText: statusText)
            }
            // VR линза формасы — дөңгеленген тіктөртбұрыш
            .clipShape(
                RoundedRectangle(
                    cornerRadius: min(geo.size.width, geo.size.height) * 0.14,
                    style: .continuous
                )
            )
        }
    }
}

// MARK: - VR Mode View

struct VRModeView: View {
    let session: AVCaptureSession
    @Binding var isVRMode: Bool

    @StateObject private var gyro = GyroManager()
    @State private var isListening = false
    @State private var statusText = ""

    var body: some View {
        GeometryReader { geo in
            let eyeWidth  = max(1, geo.size.width / 2 - 6)
            let eyeHeight = max(1, geo.size.height - 16)

            ZStack {
                // Black background (VR headset frame)
                Color.black.ignoresSafeArea()

                HStack(spacing: 4) {
                    // Сол көз
                    VREyeView(
                        session: session,
                        gyro: gyro,
                        isListening: isListening,
                        statusText: statusText
                    )
                    .frame(width: eyeWidth, height: eyeHeight)

                    // Оң көз
                    VREyeView(
                        session: session,
                        gyro: gyro,
                        isListening: isListening,
                        statusText: statusText
                    )
                    .frame(width: eyeWidth, height: eyeHeight)
                }

                // Close button
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismissVR()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(16)
                        }
                    }
                    Spacer()
                }

                // Mic button
                VStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            isListening.toggle()
                            statusText = isListening ? "Тыңдап жатыр..." : ""
                        }
                    } label: {
                        Circle()
                            .fill(.black.opacity(0.5))
                            .overlay {
                                Circle().strokeBorder(
                                    isListening ? Color.green.opacity(0.7) : .white.opacity(0.25),
                                    lineWidth: 1.2
                                )
                            }
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: isListening ? "mic.fill" : "mic")
                                    .font(.system(size: 17))
                                    .foregroundStyle(isListening ? .green : .white.opacity(0.6))
                            }
                    }
                    .padding(.bottom, 14)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear {
            gyro.start()
            enableLandscape()
        }
        .onDisappear {
            gyro.stop()
        }
    }

    private func dismissVR() {
        gyro.stop()
        OrientationManager.shared.isVRMode = false
        isVRMode = false
    }

    // MARK: - Orientation helpers

    private func enableLandscape() {
        OrientationManager.shared.isVRMode = true
        if #available(iOS 16.0, *) {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UINavigationController.attemptRotationToDeviceOrientation()
        }
    }


}

// MARK: - VR Mode Button (for mode picker)

struct VRModeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "visionpro")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 18)

                Text("VR режим")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 0)

                Text("NEW")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.purple.opacity(0.65)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(width: 140, alignment: .leading)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .light)
                    .overlay {
                        Capsule().fill(LinearGradient(
                            colors: [.purple.opacity(0.2), .blue.opacity(0.1)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        Capsule().fill(LinearGradient(
                            colors: [.white.opacity(0.3), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        Capsule().strokeBorder(.purple.opacity(0.45), lineWidth: 1)
                    }
            }
            .shadow(color: .purple.opacity(0.15), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
