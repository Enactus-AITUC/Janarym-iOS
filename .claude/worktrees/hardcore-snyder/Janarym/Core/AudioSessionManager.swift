import AVFoundation

/// Singleton that sets up AVAudioSession ONCE at app launch.
/// Camera + mic + TTS all coexist using playAndRecord + mixWithOthers.
enum AudioSessionManager {

    static func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            print("AudioSession: configure error \(error)")
        }
    }
}
