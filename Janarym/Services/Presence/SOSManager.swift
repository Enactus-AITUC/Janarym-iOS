import AVFoundation
import UIKit

/// SOS триггері:
///   1. Дыбыс батырмасын 3 рет жылдам басу (2 секунд ішінде)
///   2. Дауыспен "жәрдем" / "помогите" / "SOS"
///
/// onSOS callback шақырылғанда AssistantCoordinator Firestore-қа жазады + TTS айтады.
final class SOSManager: NSObject {

    static let shared = SOSManager()

    /// SOS іске қосылғанда шақырылады
    var onSOS: (() -> Void)?

    private var pressTimestamps: [Date] = []
    private var isMonitoring = false
    private let session = AVAudioSession.sharedInstance()

    private override init() { super.init() }

    // MARK: - Public

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        session.addObserver(self, forKeyPath: "outputVolume",
                            options: [.new], context: nil)
        try? session.setActive(true)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        session.removeObserver(self, forKeyPath: "outputVolume")
    }

    /// Дауыспен SOS — тек өте нақты фраза (кездейсоқ триггер болмасын)
    static func containsSOSCommand(_ text: String) -> Bool {
        let n = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Тек нақты қысқа фраза — бір сөз емес, толық команда
        let exact = ["sos жіберу", "sos жибер", "sos отправить", "отправить sos"]
        return exact.contains(where: { n == $0 || n.hasPrefix($0) })
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?,
                                of object: Any?,
                                change: [NSKeyValueChangeKey: Any]?,
                                context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume" else { return }

        let now = Date()
        pressTimestamps.append(now)
        // 5 секундтан ескі өшір
        pressTimestamps = pressTimestamps.filter { now.timeIntervalSince($0) < 5.0 }

        if pressTimestamps.count >= 10 {
            pressTimestamps.removeAll()
            DispatchQueue.main.async { [weak self] in
                self?.onSOS?()
            }
        }
    }
}
