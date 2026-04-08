import AVFoundation

final class SpeechSynthesizerService: NSObject, ObservableObject {

    @Published var isSpeaking = false

    var onFinished: (() -> Void)?

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: - Public

    func speak(_ text: String, language: DetectedLanguage) {
        guard !text.isEmpty else { onFinished?(); return }
        stop()
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = OnboardingStore.shared.profile.speechRate.avRate

        switch language {
        case .kazakh:  utterance.voice = AVSpeechSynthesisVoice(language: "kk-KZ")
                                      ?? AVSpeechSynthesisVoice(language: "ru-RU")
        case .russian: utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        default:       utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesizerService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.onFinished?()
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
