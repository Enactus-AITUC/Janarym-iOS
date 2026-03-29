import Foundation
import CoreLocation
import UIKit

/// Member жағы: локация + батарея + соңғы фото → Firestore-ке жіберіп тұрады
final class UserPresenceService: NSObject {

    static let shared = UserPresenceService()

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var photoTimer: Timer?
    private(set) var lastLocation: CLLocation?
    private var userId: String?

    /// AssistantCoordinator арқылы CameraService-ке қол жеткізу
    var capturePhoto: (() -> Data?)? = nil

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 30
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: - Public

    func start(userId: String) {
        self.userId = userId
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()

        // 30 секунд сайын presence жаңарту
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.uploadPresence(photoURL: nil)
        }
        uploadPresence(photoURL: nil)

        // 5 минут сайын соңғы камера кадрын Storage-ке жүктеу
        photoTimer?.invalidate()
        photoTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let data = self?.capturePhoto?() else { return }
            self?.uploadPhotoAndPresence(jpegData: data)
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        photoTimer?.invalidate()
        photoTimer = nil
    }

    /// Камера кадрын жүктеп, presence-ті жаңарту
    func uploadPhotoAndPresence(jpegData: Data) {
        guard let uid = userId else { return }
        Task {
            let url = await StorageService.shared.uploadLastPhoto(data: jpegData, userId: uid)
            uploadPresence(photoURL: url)
        }
    }

    // MARK: - Private

    private func uploadPresence(photoURL: String?) {
        guard let uid = userId, let loc = lastLocation else { return }
        let battery = max(0, Double(UIDevice.current.batteryLevel))
        Task {
            await FirestoreService.shared.updatePresence(
                userId: uid,
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude,
                battery: battery,
                photoURL: photoURL
            )
        }
    }
}

extension UserPresenceService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }
}
