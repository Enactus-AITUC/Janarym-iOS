import AVFoundation
import UIKit

final class CameraService: NSObject, ObservableObject {

    @Published var isRunning  = false
    @Published var isStarting = false   // UI overlay үшін
    @Published var error: AppError?

    let session = AVCaptureSession()

    private let sessionQueue  = DispatchQueue(label: "com.janarym.camera")
    private var isConfigured   = false
    private var sessionStarting = false  // sessionQueue-дағы internal flag
    private var retryCount    = 0
    private let maxRetries    = 2
    private var timeoutWork: DispatchWorkItem?

    private var activeVideoDevice: AVCaptureDevice?

    // MARK: - Frame capture (Vision үшін)
    private let frameOutput = AVCaptureVideoDataOutput()
    private let frameLock   = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?

    // MARK: - Auto torch (frame brightness негізінде)
    var autoTorchEnabled = false
    private var torchFrameCounter = 0
    private var currentTorchState = false

    override init() {
        super.init()
        observeSessionNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

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
        DispatchQueue.main.async {
            self.error = nil
        }

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
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.sessionStarting else { return }

            self.sessionStarting = true
            DispatchQueue.main.async { self.isStarting = true }
            self.scheduleStartupTimeout()

            if !self.isConfigured {
                self.configureSession()
            }

            // configureSession сәтсіз болса — тоқта
            guard self.isConfigured else {
                self.finishStart(running: false)
                return
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            self.finishStart(running: self.session.isRunning)
        }
    }

    private func scheduleStartupTimeout() {
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isRunning else { return }
            // Reset flags — future start() calls жұмыс жасайды
            self.sessionStarting = false
            self.isConfigured = false
            DispatchQueue.main.async {
                self.isStarting = false
                // Auto-retry (maxRetries рет)
                if self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.start()
                    }
                } else {
                    self.retryCount = 0
                    self.error = .cameraUnavailable
                }
            }
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)  // 5s → 3s
    }

    private func finishStart(running: Bool) {
        DispatchQueue.main.async {
            self.timeoutWork?.cancel()
            self.timeoutWork = nil
            self.sessionStarting = false
            self.isStarting  = false
            self.retryCount  = 0
            self.isRunning   = running
            self.error       = running ? nil : .cameraUnavailable
        }
    }

    func stop() {
        timeoutWork?.cancel()
        timeoutWork = nil
        retryCount = 0
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.sessionStarting = false
            DispatchQueue.main.async { self.isStarting = false }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            if self.currentTorchState {
                self.setTorchState(on: false)
                self.currentTorchState = false
            }
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
        resetSessionGraphLocked()

        // .high барлық iPhone-да жұмыс жасамайды — fallback .medium
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }

        // Камера құрылғысы
        guard let device = preferredVideoDevice() else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = .cameraUnavailable }
            return
        }
        activeVideoDevice = device

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

    private func resetSessionGraphLocked() {
        session.inputs.forEach { session.removeInput($0) }
        frameOutput.setSampleBufferDelegate(nil, queue: nil)
        session.outputs.forEach { session.removeOutput($0) }
        activeVideoDevice = nil
        previousPixelBuffer = nil
        latestPixelBuffer = nil
        torchFrameCounter = 0
        currentTorchState = false
    }

    private func preferredVideoDevice() -> AVCaptureDevice? {
        if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return back
        }
        if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return front
        }
        return AVCaptureDevice.default(for: .video)
    }

    // MARK: - Torch

    func setTorch(on: Bool) {
        applyTorchOnSessionQueue(on: on)
    }

    private func applyTorchOnSessionQueue(on: Bool) {
        sessionQueue.async { [weak self] in
            self?.setTorchState(on: on)
        }
    }

    var currentBrightness: Float {
        guard let device = activeVideoDevice ?? preferredVideoDevice() else { return 1 }
        let iso    = device.iso
        let maxISO = device.activeFormat.maxISO
        return max(0, min(1, 1.0 - (iso / maxISO)))
    }

    private func setTorchState(on: Bool) {
        guard let device = activeVideoDevice,
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

    // MARK: - Runtime recovery

    private func observeSessionNotifications() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
    }

    @objc
    private func handleSessionRuntimeError(_ notification: Notification) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.isConfigured    = false
            self.sessionStarting     = false
            self.activeVideoDevice = nil
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.isStarting = false
                self.isRunning  = false
                // Auto-retry on runtime error
                if self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.start()
                    }
                } else {
                    self.retryCount = 0
                    self.error = .cameraUnavailable
                }
            }
        }
    }

    @objc
    private func handleSessionWasInterrupted(_ notification: Notification) {
        _ = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber
    }

    @objc
    private func handleSessionInterruptionEnded(_ notification: Notification) {
        start()
    }

    // MARK: - Torch change callback

    /// Called on main thread when auto-torch switches on or off.
    var onTorchChanged: ((Bool) -> Void)?

    // MARK: - Motion detection

    var onMotionDetected: (() -> Void)?
    private var previousPixelBuffer: CVPixelBuffer?
    private var lastMotionTime: CFAbsoluteTime = 0
    private let motionCooldown: CFAbsoluteTime = 0.8
    private let motionThreshold: Float = 0.018

    private func checkMotion(current: CVPixelBuffer) {
        guard onMotionDetected != nil else { return }
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
                    DispatchQueue.main.async { self.onTorchChanged?(shouldBeOn) }
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
