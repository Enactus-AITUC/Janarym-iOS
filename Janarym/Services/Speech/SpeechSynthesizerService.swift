import AVFoundation

final class SpeechSynthesizerService: NSObject, ObservableObject {

    @Published var isSpeaking = false

    var onFinished: (() -> Void)?

    private var audioPlayer: AVAudioPlayer?
    private var currentTask: Task<Void, Never>?

    // AVSpeechSynthesizer тек API жетімсіз болса пайдаланылады
    private let fallbackSynth = AVSpeechSynthesizer()

    override init() {
        super.init()
        fallbackSynth.delegate = self
    }

    // MARK: - Public

    func speak(_ text: String, language: DetectedLanguage) {
        guard !text.isEmpty else { onFinished?(); return }
        stop()
        isSpeaking = true

        currentTask = Task { [weak self] in
            // VIP → OpenAI TTS (nova), Free/Premium → тегін AVSpeechSynthesizer
            let isVIP = await MainActor.run { SubscriptionManager.shared.tier.canUseOpenAITTS }
            if isVIP {
                await self?.speakViaOpenAI(text)
            } else {
                await self?.speakFallback(text)
            }
        }
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        if fallbackSynth.isSpeaking { fallbackSynth.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    // MARK: - OpenAI TTS (tts-1 + nova — қазақша/орысша автодетекция)

    private func speakViaOpenAI(_ text: String) async {
        guard !AppConfig.openAIAPIKey.isEmpty else {
            await speakFallback(text)
            return
        }

        // avRate: slow=0.42, normal=0.50, fast=0.58 → openai speed: *2.0
        let speed = max(0.25, min(4.0, Double(OnboardingStore.shared.profile.speechRate.avRate) * 2.0))

        let body: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": "nova",        // Табиғи әйел дауысы — қазақша жақсы айтады
            "response_format": "mp3",
            "speed": speed
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            await speakFallback(text)
            return
        }

        var request = OpenAIClient.request(
            path: "/v1/audio/speech",
            body: bodyData,
            contentType: "application/json"
        )
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard !Task.isCancelled else { return }

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty else {
                await speakFallback(text)
                return
            }

            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("janarym_tts.mp3")
            try data.write(to: tmpURL)

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                do {
                    self.audioPlayer = try AVAudioPlayer(contentsOf: tmpURL)
                    self.audioPlayer?.delegate = self
                    self.audioPlayer?.play()
                } catch {
                    self.isSpeaking = false
                    self.onFinished?()
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            await speakFallback(text)
        }
    }

    // MARK: - Fallback (API қолжетімсіз болса)

    @MainActor
    private func speakFallback(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = OnboardingStore.shared.profile.speechRate.avRate
        utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        isSpeaking = true
        fallbackSynth.speak(utterance)
    }
}

// MARK: - AVAudioPlayerDelegate (OpenAI TTS аяқталғанда)

extension SpeechSynthesizerService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.onFinished?()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate (fallback аяқталғанда)

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
