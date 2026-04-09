import Speech
import AVFoundation

// MARK: - Command enum

enum RecognizedVoiceCommand: Equatable {
    case settings
    case medCard
    case camera
    case back
    case recordSymptom
    case whereIsParent
    case sos
    case torchOn
    case torchOff
    case torchToggle
    case askTime
    case wakeWord
}

// MARK: - Service

final class VoiceCommandService: NSObject, ObservableObject {

    @Published private(set) var isListening = false
    @Published private(set) var lastCommand: RecognizedVoiceCommand?

    // MARK: - Private

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    private var isActive  = false
    private var isPaused  = false
    private var restartTimer: Timer?

    // Prevent same command re-firing within 2.5s
    private var lastFiredText = ""
    private var lastFiredAt:  Date = .distantPast

    private let commandMap: [(keywords: [String], cmd: RecognizedVoiceCommand)] = [
        // Wake word (highest priority — check before others)
        (["жанарым"],                                                   .wakeWord),
        // Navigation
        (["баптаулар", "настройки"],                                   .settings),
        (["медкарта", "медициналық карта", "мед карта", "медкарту"],   .medCard),
        (["камера", "суретке"],                                        .camera),
        (["артқа", "үй", "назад", "домой"],                           .back),
        (["жағдайымды жазу", "симптом", "жазу"],                      .recordSymptom),
        (["анам қайда", "әкем қайда", "ата-анам", "родители где"],    .whereIsParent),
        (["sos", "сос", "жәрдем", "дабыл", "помощь", "тревога"],     .sos),
        // Torch
        (["фонарь қос", "фонарьды қос", "фонарь жақ", "включи фонарь"], .torchOn),
        (["фонарь өшір", "фонарьды өшір", "выключи фонарь"],           .torchOff),
        (["фонарь"],                                                    .torchToggle),
        // Time
        (["сағат нешеде", "сағат нешe", "неше сағат", "который час", "сколько времени"], .askTime),
    ]

    // MARK: - Init

    override init() {
        // Kazakh first, Russian fallback
        let kk = SFSpeechRecognizer(locale: Locale(identifier: "kk-KZ"))
        recognizer = (kk?.isAvailable == true) ? kk : SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
        super.init()
        recognizer?.delegate = self
    }

    // MARK: - Public API

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self, status == .authorized else { return }
            DispatchQueue.main.async {
                self.isActive = true
                self.isPaused = false
                self.startCycle()
            }
        }
    }

    func stop() {
        isActive  = false
        isPaused  = false
        teardown()
        DispatchQueue.main.async { self.isListening = false }
    }

    /// Call before PTT recording starts to avoid AVAudioEngine conflicts
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        teardown()
        DispatchQueue.main.async { self.isListening = false }
    }

    /// Call after PTT recording finishes
    func resume() {
        guard isActive, isPaused else { return }
        isPaused = false
        startCycle()
    }

    // MARK: - Cycle

    private func startCycle() {
        guard isActive, !isPaused else { return }
        teardown()

        guard let rec = recognizer, rec.isAvailable else {
            scheduleRestart(after: 3); return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        recognitionRequest = req

        let node = audioEngine.inputNode
        node.removeTap(onBus: 0)
        let fmt = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak req] buf, _ in
            req?.append(buf)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            scheduleRestart(after: 2); return
        }

        DispatchQueue.main.async { self.isListening = true }

        recognitionTask = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.match(text: result.bestTranscription.formattedString)
            }
            if error != nil || result?.isFinal == true {
                self.scheduleRestart(after: 0.4)
            }
        }

        // Restart before Apple's 60 s hard limit
        scheduleAutoRestart(after: 50)
    }

    private func match(text: String) {
        let lower = text.lowercased()
        let now   = Date()
        guard lower != lastFiredText || now.timeIntervalSince(lastFiredAt) > 2.5 else { return }

        for entry in commandMap {
            for kw in entry.keywords where lower.contains(kw.lowercased()) {
                lastFiredText = lower
                lastFiredAt   = now
                DispatchQueue.main.async { self.lastCommand = entry.cmd }
                return
            }
        }
    }

    // MARK: - Helpers

    private func teardown() {
        restartTimer?.invalidate(); restartTimer = nil
        recognitionTask?.cancel(); recognitionTask = nil
        recognitionRequest?.endAudio(); recognitionRequest = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
    }

    private func scheduleRestart(after delay: TimeInterval) {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.isActive, !self.isPaused else { return }
            self.startCycle()
        }
    }

    private func scheduleAutoRestart(after delay: TimeInterval) {
        // Only sets if no existing restart is pending
        guard restartTimer == nil else { return }
        restartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.isActive, !self.isPaused else { return }
            self.startCycle()
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension VoiceCommandService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer,
                          availabilityDidChange available: Bool) {
        if available, isActive, !isPaused {
            startCycle()
        }
    }
}
