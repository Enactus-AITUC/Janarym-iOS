import AVFoundation
import SwiftUI

final class PermissionManager: ObservableObject {

    @Published var cameraGranted = false
    @Published var microphoneGranted = false
    @Published var allGranted = false

    private func updateAllGranted() {
        let granted = cameraGranted && microphoneGranted
        if allGranted != granted {
            allGranted = granted
        }
    }

    func checkAll() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        microphoneGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        updateAllGranted()
    }

    func requestAll() {
        requestCamera { [weak self] in
            self?.requestMicrophone { }
        }
    }

    private func requestCamera(completion: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            DispatchQueue.main.async {
                self.cameraGranted = true
                self.updateAllGranted()
                completion()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraGranted = granted
                    self?.updateAllGranted()
                    completion()
                }
            }
        default:
            DispatchQueue.main.async {
                self.cameraGranted = false
                self.updateAllGranted()
                completion()
            }
        }
    }

    private func requestMicrophone(completion: @escaping () -> Void) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            DispatchQueue.main.async {
                self.microphoneGranted = true
                self.updateAllGranted()
                completion()
            }
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.microphoneGranted = granted
                    self?.updateAllGranted()
                    completion()
                }
            }
        default:
            DispatchQueue.main.async {
                self.microphoneGranted = false
                self.updateAllGranted()
                completion()
            }
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
