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
        if synth.isSpeaking {
            synth.stopSpeaking(at: .word)
            isSpeaking = false
        }
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = OnboardingStore.shared.profile.speechRate.avPreviewRate
        utterance.pitchMultiplier = 0.76
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = 0.04
        utterance.voice = preferredVoice(for: language)

        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .word) }
        isSpeaking = false
    }

    private func preferredVoice(for language: DetectedLanguage) -> AVSpeechSynthesisVoice? {
        let preferredLanguages: [String]
        switch language {
        case .kazakh:
            preferredLanguages = ["kk-KZ", "ru-RU"]
        case .russian:
            preferredLanguages = ["ru-RU"]
        default:
            preferredLanguages = ["en-US"]
        }

        let voices = AVSpeechSynthesisVoice.speechVoices()
        let maleHints = [
            "aaron", "alex", "daniel", "grandpa", "rocko", "reed", "nicky",
            "oleg", "yuri", "yuriy", "maxim", "damir", "nurlan", "sergey", "timur"
        ]

        for languageCode in preferredLanguages {
            let matching = voices.filter { $0.language == languageCode }

            if let siriMale = matching.first(where: { voice in
                let haystack = "\(voice.name) \(voice.identifier)".lowercased()
                return haystack.contains("siri") && maleHints.contains(where: haystack.contains)
            }) {
                return siriMale
            }

            if let male = matching.first(where: { voice in
                let haystack = "\(voice.name) \(voice.identifier)".lowercased()
                return maleHints.contains(where: haystack.contains)
            }) {
                return male
            }

            if let premium = matching.max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
                return premium
            }
        }

        return AVSpeechSynthesisVoice(language: preferredLanguages.first ?? "en-US")
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
