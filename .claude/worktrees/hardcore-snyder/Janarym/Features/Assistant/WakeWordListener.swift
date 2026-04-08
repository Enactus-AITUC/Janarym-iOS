import AVFoundation
import Speech

final class WakeWordListener: ObservableObject {

    @Published var isListening = false

    var onWakeWordDetected: (() -> Void)?
    /// Wake word жоқта тікелей режим командасы анықталса шақырылады (modeKey жібереді)
    var onModeCommandDetected: ((String) -> Void)?
    /// Called after tearDown completes (audio engine fully stopped)
    var onTearDownComplete: (() -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var shouldBeListening = false
    private var restartWorkItem: DispatchWorkItem?
    private var consecutiveErrors = 0

    // Locale priority: kk-KZ → ru-RU → en-US
    private static let locales = ["kk-KZ", "ru-RU", "en-US"]

    init() {
        speechRecognizer = Self.bestAvailableRecognizer()
    }

    private static func bestAvailableRecognizer() -> SFSpeechRecognizer? {
        for id in locales {
            if let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.isAvailable {
                print("WakeWord: using locale \(id)")
                return r
            }
        }
        return SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Public

    func startListening() {
        shouldBeListening = true
        guard !isListening else { return }
        beginRecognition()
    }

    func stopListening() {
        shouldBeListening = false
        restartWorkItem?.cancel()
        tearDown()
    }

    // MARK: - Private

    private func beginRecognition() {
        guard shouldBeListening else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }

        if speechRecognizer == nil || !(speechRecognizer?.isAvailable ?? false) {
            speechRecognizer = Self.bestAvailableRecognizer()
        }
        guard let recognizer = speechRecognizer else { return }

        tearDown()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode

        // Use outputFormat — the downstream format the node actually produces
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        let format: AVAudioFormat
        if nativeFormat.channelCount > 0 && nativeFormat.sampleRate > 0 {
            format = nativeFormat
        } else {
            format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: 16000, channels: 1,
                                   interleaved: false)!
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard buffer.frameLength > 0 else { return }
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            consecutiveErrors = 0
        } catch {
            print("WakeWord: engine start error \(error)")
            tearDown()
            scheduleRestart(delay: 2.0)
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                print("WakeWord heard: \(text)")

                if StringNormalizer.containsWakeWord(text) {
                    self.tearDown()
                    DispatchQueue.main.async { self.onWakeWordDetected?() }
                    return
                }

                // Тікелей режим командасы — wake word жоқта да ауыстырады
                if let modeKey = StringNormalizer.detectModeKey(text) {
                    self.tearDown()
                    DispatchQueue.main.async { self.onModeCommandDetected?(modeKey) }
                    self.scheduleRestart(delay: 0.5)
                    return
                }

                // Too many words accumulated — reset to avoid garbage matches
                let wordCount = text.split(separator: " ").count
                if wordCount > 10 || text.count > 70 {
                    self.tearDown()
                    self.scheduleRestart(delay: 0.15)
                    return
                }
            }

            if error != nil || (result?.isFinal ?? false) {
                self.consecutiveErrors += 1
                self.tearDown()
                let delay = min(0.3 * Double(self.consecutiveErrors), 3.0)
                self.scheduleRestart(delay: delay)
            }
        }

        DispatchQueue.main.async { self.isListening = true }
    }

    private func tearDown() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        DispatchQueue.main.async {
            self.isListening = false
            self.onTearDownComplete?()
        }
    }

    private func scheduleRestart(delay: TimeInterval = 0.5) {
        guard shouldBeListening else { return }
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.beginRecognition() }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
