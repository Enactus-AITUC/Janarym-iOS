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

    /// Whisper нәтижесін тексеру — дауыспен SOS
    static func containsSOSCommand(_ text: String) -> Bool {
        let n = text.lowercased()
        let keywords = ["жәрдем", "жардем", "помогите", "помоги", "sos", "сос"]
        return keywords.contains(where: { n.contains($0) })
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?,
                                of object: Any?,
                                change: [NSKeyValueChangeKey: Any]?,
                                context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume" else { return }

        let now = Date()
        pressTimestamps.append(now)
        // 2 секундтан ескі өшір
        pressTimestamps = pressTimestamps.filter { now.timeIntervalSince($0) < 2.0 }

        if pressTimestamps.count >= 3 {
            pressTimestamps.removeAll()
            DispatchQueue.main.async { [weak self] in
                self?.onSOS?()
            }
        }
    }
}
