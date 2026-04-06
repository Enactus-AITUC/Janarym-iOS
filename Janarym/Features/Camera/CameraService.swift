import AVFoundation
import UIKit

final class CameraService: NSObject, ObservableObject {

    @Published var isRunning = false
    @Published var error: AppError?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.janarym.camera")
    private var isConfigured = false
    private var timeoutWork: DispatchWorkItem?

    // MARK: - Frame capture (Vision үшін)
    private let frameOutput = AVCaptureVideoDataOutput()
    private let frameLock   = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?

    // MARK: - Auto torch (frame brightness негізінде)
    var autoTorchEnabled = false
    private var torchFrameCounter = 0
    private var currentTorchState = false

    // MARK: - Frame capture public API

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

    func captureCurrentFrameBase64(maxEdge: CGFloat = 768) -> String? {
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
                if granted {
                    self?.startSession()
                } else {
                    DispatchQueue.main.async {
                        self?.error = .permissionDenied("Камера")
                    }
                }
            }
        default:
            DispatchQueue.main.async { self.error = .permissionDenied("Камера") }
        }
    }

    private func startSession() {
        // 5 секундтық timeout — камера ашылмаса қате көрсету
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isRunning else { return }
            print("⚠️ CameraService: 5 секунд ішінде камера ашылмады")
            self.error = .cameraUnavailable
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                self.configureSession()
            }

            // configureSession сәтсіз болса — тоқта
            guard self.isConfigured else { return }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            // startRunning() нәтижесін тексеру
            let running = self.session.isRunning
            DispatchQueue.main.async {
                self.timeoutWork?.cancel()
                self.timeoutWork = nil
                if running {
                    self.isRunning = true
                    self.error = nil
                } else {
                    print("⚠️ CameraService: session.startRunning() сәтсіз болды")
                    self.error = .cameraUnavailable
                }
            }
        }
    }

    func stop() {
        timeoutWork?.cancel()
        timeoutWork = nil
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

        // Егер бұрын конфигурацияланған болса — қайта жасамау
        if isConfigured { return }

        session.beginConfiguration()

        // .high барлық iPhone-да жұмыс жасамайды — fallback .medium
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }

        // Камера құрылғысы
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = .cameraUnavailable }
            return
        }

        // Input
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = .cameraUnavailable }
            return
        }
        session.addInput(input)

        // Frame output — Vision үшін
        frameOutput.alwaysDiscardsLateVideoFrames = true
        frameOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        frameOutput.setSampleBufferDelegate(
            self,
            queue: DispatchQueue(label: "com.janarym.frame", qos: .utility)
        )
        if session.canAddOutput(frameOutput) {
            session.addOutput(frameOutput)
        }

        session.commitConfiguration()
        isConfigured = true
    }

    // MARK: - Torch

    func setTorch(on: Bool) {
        applyTorchOnSessionQueue(on: on)
    }

    private func applyTorchOnSessionQueue(on: Bool) {
        sessionQueue.async { [weak self] in
            guard self != nil else { return }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  device.hasTorch, device.isTorchAvailable else { return }
            do {
                try device.lockForConfiguration()
                if on {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    var currentBrightness: Float {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return 1 }
        let iso    = device.iso
        let maxISO = device.activeFormat.maxISO
        return max(0, min(1, 1.0 - (iso / maxISO)))
    }

    // MARK: - Motion detection

    var onMotionDetected: (() -> Void)?
    private var previousPixelBuffer: CVPixelBuffer?
    private var lastMotionTime: CFAbsoluteTime = 0
    private let motionCooldown: CFAbsoluteTime = 0.8
    private let motionThreshold: Float = 0.018

    private func checkMotion(current: CVPixelBuffer) {
        guard let previous = previousPixelBuffer else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastMotionTime >= motionCooldown else { return }

        CVPixelBufferLockBaseAddress(current,  .readOnly)
        CVPixelBufferLockBaseAddress(previous, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(current,  .readOnly)
            CVPixelBufferUnlockBaseAddress(previous, .readOnly)
        }

        let width  = CVPixelBufferGetWidth(current)
        let height = CVPixelBufferGetHeight(current)
        guard let curBase  = CVPixelBufferGetBaseAddress(current),
              let prevBase = CVPixelBufferGetBaseAddress(previous) else { return }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(current)
        let stepX = max(1, width  / 24)
        let stepY = max(1, height / 24)
        var diffSum: Float = 0
        var count = 0

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let offset = y * bytesPerRow + x * 4
                let cur  = curBase .advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                let prev = prevBase.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                let diff = (abs(Float(cur[0]) - Float(prev[0])) +
                            abs(Float(cur[1]) - Float(prev[1])) +
                            abs(Float(cur[2]) - Float(prev[2]))) / (255.0 * 3.0)
                diffSum += diff
                count   += 1
                x += stepX
            }
            y += stepY
        }

        guard count > 0, (diffSum / Float(count)) > motionThreshold else { return }
        lastMotionTime = now
        onMotionDetected?()
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

        checkMotion(current: pixelBuffer)
        previousPixelBuffer = pixelBuffer

        // Auto-torch: ~2 секунд сайын (30fps × 60 frame = 2s)
        if autoTorchEnabled {
            torchFrameCounter += 1
            if torchFrameCounter % 60 == 0 {
                let brightness = frameBrightness(pixelBuffer)
                let shouldBeOn = brightness < 0.12
                if shouldBeOn != currentTorchState {
                    currentTorchState = shouldBeOn
                    applyTorchOnSessionQueue(on: shouldBeOn)
                }
            }
        }
    }

    private func frameBrightness(_ buffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 1 }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let stepX = max(1, w / 20)
        let stepY = max(1, h / 20)
        var sum: Float = 0
        var n = 0
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                let p = base.advanced(by: y * bpr + x * 4).assumingMemoryBound(to: UInt8.self)
                sum += Float(p[0]) * 0.114 + Float(p[1]) * 0.587 + Float(p[2]) * 0.299
                n += 1
                x += stepX
            }
            y += stepY
        }
        return n > 0 ? (sum / Float(n)) / 255.0 : 1.0
    }
}
