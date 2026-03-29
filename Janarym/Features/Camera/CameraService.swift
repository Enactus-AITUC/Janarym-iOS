import AVFoundation
import UIKit

final class CameraService: NSObject, ObservableObject {

    @Published var isRunning = false
    @Published var error: AppError?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.janarym.camera")
    private var isConfigured = false

    // MARK: - Frame capture (Vision үшін)
    private let frameOutput = AVCaptureVideoDataOutput()
    private let frameLock   = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?

    /// Камераның ағымдағы кадрын JPEG Data ретінде қайтарады (Firebase Storage үшін)
    func captureCurrentFrameJPEG(maxEdge: CGFloat = 512) -> Data? {
        frameLock.lock()
        let buffer = latestPixelBuffer
        frameLock.unlock()
        guard let buffer else { return nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let ciCtx   = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ciCtx.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let raw = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        let scale = min(maxEdge / raw.size.width, maxEdge / raw.size.height, 1.0)
        let size  = CGSize(width: raw.size.width * scale, height: raw.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in raw.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.65)
    }

    /// Камераның ағымдағы кадрын JPEG base64 ретінде қайтарады (GPT-4o Vision үшін)
    func captureCurrentFrameBase64(maxEdge: CGFloat = 768) -> String? {
        frameLock.lock()
        let buffer = latestPixelBuffer
        frameLock.unlock()

        guard let buffer else { return nil }

        let ciImage = CIImage(cvPixelBuffer: buffer)
        let ciCtx   = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ciCtx.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        // Portrait default — app portrait-only
        let raw = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

        // Кескінді maxEdge-тен аспайтын ете кіші ет (token үнемдеу)
        let scale = min(maxEdge / raw.size.width, maxEdge / raw.size.height, 1.0)
        let size  = CGSize(width: raw.size.width * scale, height: raw.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            raw.draw(in: CGRect(origin: .zero, size: size))
        }

        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else { return nil }
        return jpeg.base64EncodedString()
    }

    // MARK: - Session control

    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else {
                    DispatchQueue.main.async { self?.error = .permissionDenied("Камера") }
                    return
                }
                self?.startSession()
            }
        default:
            DispatchQueue.main.async { self.error = .permissionDenied("Камера") }
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured { self.configureSession() }
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.error = nil
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - Session configuration

    private func configureSession() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            DispatchQueue.main.async { self.error = .permissionDenied("Камера") }
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = .cameraUnavailable }
            return
        }

        session.addInput(input)

        // Frame capture output — Vision үшін
        frameOutput.alwaysDiscardsLateVideoFrames = true
        frameOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        frameOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.janarym.frame", qos: .utility))
        if session.canAddOutput(frameOutput) {
            session.addOutput(frameOutput)
        }

        session.commitConfiguration()
        isConfigured = true
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameLock.lock()
        latestPixelBuffer = pixelBuffer
        frameLock.unlock()
    }
}
