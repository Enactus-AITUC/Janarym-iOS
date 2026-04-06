import AVFoundation
import Foundation

// MARK: - State

enum GeminiLiveState: Equatable {
    case disconnected
    case connecting
    case idle
    case recording
    case processing
    case speaking
}

// MARK: - GeminiLiveService
//
// Gemini Live API — WebSocket BidiGenerateContent
// Model: models/gemini-2.5-flash-native-audio-latest
// Input:  audio/wav (16kHz, 16-bit, mono PCM) + optional image/jpeg
// Output: audio/pcm (24kHz, 16-bit, mono PCM) → WAV → AVAudioPlayer

@MainActor
final class GeminiLiveService: NSObject, ObservableObject {

    @Published var state: GeminiLiveState = .disconnected
    @Published var isConnected = false
    @Published var errorMessage: String?

    /// Мәтін жауабы болса шақырылады (TTS fallback)
    var onResponse: ((String) -> Void)?

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    private var accumulatedText  = ""
    private var accumulatedAudio = Data()

    private var audioPlayer: AVAudioPlayer?

    private let wsBase = "wss://generativelanguage.googleapis.com/ws/"
        + "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    private let model  = "models/gemini-2.5-flash-native-audio-latest"

    // MARK: - Connect / Disconnect

    func connect() {
        guard state == .disconnected else { return }
        guard !AppConfig.geminiAPIKey.isEmpty else {
            print("⚠️ GeminiLive: GEMINI_API_KEY жоқ")
            errorMessage = "API key жоқ"
            return
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        state        = .connecting
        errorMessage = nil

        guard let url = URL(string: "\(wsBase)?key=\(AppConfig.geminiAPIKey)") else { return }
        print("🔌 GeminiLive: қосылуда (\(model))...")

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 300
        urlSession    = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        startReceiving()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        audioRecorder?.stop()
        audioRecorder = nil
        audioPlayer?.stop()
        audioPlayer   = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession    = nil
        isConnected   = false
        state         = .disconnected
        print("🔌 GeminiLive: ажыратылды")
    }

    // MARK: - Setup

    private func sendSetup() {
        let payload: [String: Any] = [
            "setup": [
                "model": model,
                "generation_config": [
                    "response_modalities": ["AUDIO"]   // native audio model → AUDIO ғана
                ],
                "system_instruction": [
                    "parts": [["text": AppConfig.systemPrompt]]
                ]
            ]
        ]
        print("📤 GeminiLive: setup жіберілуде (AUDIO modality)...")
        send(json: payload)
    }

    // MARK: - Push-to-Talk

    func startPTT() {
        print("🎙️ GeminiLive: startPTT — state=\(state)")
        if state == .disconnected { connect() }
        guard state == .idle || state == .connecting else { return }

        audioPlayer?.stop()
        audioPlayer = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement,
                                    options: [.duckOthers, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ GeminiLive: аудио сессия (record) — \(error)")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gemini_ptt_\(Int(Date().timeIntervalSince1970)).wav")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey:             Int(kAudioFormatLinearPCM),
            AVSampleRateKey:           16000.0,
            AVNumberOfChannelsKey:     1,
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsFloatKey:     false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
            guard audioRecorder?.record() == true else {
                print("⚠️ GeminiLive: record() false")
                state = isConnected ? .idle : .connecting
                return
            }
            state = .recording
            print("✅ GeminiLive: жазу → \(url.lastPathComponent)")
        } catch {
            print("⚠️ GeminiLive: AVAudioRecorder — \(error)")
            state = isConnected ? .idle : .connecting
        }
    }

    func stopPTTAndSend(cameraService: CameraService) {
        print("🎙️ GeminiLive: stopPTT — state=\(state)")
        guard state == .recording else { return }

        audioRecorder?.stop()
        audioRecorder = nil

        state            = .processing
        accumulatedText  = ""
        accumulatedAudio = Data()

        guard let audioURL = recordingURL else { state = .idle; return }
        // Native audio model суретті қабылдамайды → тек аудио жіберіледі
        Task { await sendMedia(audioURL: audioURL) }
    }

    // MARK: - Send media

    private func sendMedia(audioURL: URL) async {
        if !isConnected {
            print("⏳ GeminiLive: қосылуды күтеді...")
            for i in 1...10 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if isConnected { break }
                if i == 10 {
                    print("⚠️ GeminiLive: қосылу timeout")
                    state = .idle
                    return
                }
            }
        }

        guard let audioData = try? Data(contentsOf: audioURL),
              audioData.count > 44 else {
            print("⚠️ GeminiLive: аудио бос")
            state = .idle
            return
        }

        print("📤 GeminiLive: аудио жіберілуде — \(audioData.count) байт")

        // Native audio model тек аудио қабылдайды, сурет жоқ
        let chunks: [[String: String]] = [
            ["mime_type": "audio/wav", "data": audioData.base64EncodedString()]
        ]
        send(json: ["realtime_input": ["media_chunks": chunks]])
    }

    // MARK: - WebSocket send

    private func send(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error {
                print("⚠️ GeminiLive send: \(error.localizedDescription)")
                Task { @MainActor [weak self] in self?.scheduleReconnect() }
            }
        }
    }

    // MARK: - Receive loop

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let msg):
                Task { @MainActor [weak self] in
                    self?.handleIncoming(msg)
                    self?.startReceiving()
                }
            case .failure(let err):
                print("⚠️ GeminiLive receive: \(err.localizedDescription)")
                Task { @MainActor [weak self] in self?.scheduleReconnect() }
            }
        }
    }

    // MARK: - Parse

    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) {
        let raw: String?
        switch message {
        case .string(let s): raw = s
        case .data(let d):   raw = String(data: d, encoding: .utf8)
        @unknown default:    return
        }
        guard let raw,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        print("📥 GeminiLive: \(raw.prefix(200))")
        parseMessage(json)
    }

    private func parseMessage(_ json: [String: Any]) {

        // 1. setupComplete
        if json["setupComplete"] != nil || json["setup_complete"] != nil {
            print("✅ GeminiLive: setup аяқталды → idle")
            isConnected       = true
            reconnectAttempts = 0
            if state == .connecting { state = .idle }
            return
        }

        // 2. serverContent
        if let sc = json["serverContent"] as? [String: Any]
                 ?? json["server_content"] as? [String: Any] {

            let turn = sc["modelTurn"] as? [String: Any]
                    ?? sc["model_turn"] as? [String: Any]

            if let parts = turn?["parts"] as? [[String: Any]] {
                for part in parts {
                    // Мәтін чанкі
                    if let text = part["text"] as? String, !text.isEmpty {
                        accumulatedText += text
                        print("📥 text chunk '\(text.prefix(60))'")
                    }

                    // Аудио чанкі — native audio model PCM жібереді
                    if let inline = part["inlineData"] as? [String: Any]
                                 ?? part["inline_data"] as? [String: Any],
                       let mime = inline["mimeType"] as? String
                               ?? inline["mime_type"] as? String,
                       mime.hasPrefix("audio"),
                       let b64 = inline["data"] as? String,
                       let chunk = Data(base64Encoded: b64) {
                        accumulatedAudio.append(chunk)
                        print("📥 audio chunk +\(chunk.count)б (total \(accumulatedAudio.count)б)")
                    }
                }
            }

            let done = sc["turnComplete"] as? Bool
                    ?? sc["turn_complete"] as? Bool
                    ?? false

            if done {
                print("✅ turnComplete — audio=\(accumulatedAudio.count)б, text=\(accumulatedText.count)с")
                handleTurnComplete()
            }
        }

        // 3. Қате
        if let err = json["error"] as? [String: Any] {
            let msg = err["message"] as? String ?? "Белгісіз қате"
            print("❌ GeminiLive API: \(msg)")
            errorMessage     = msg
            accumulatedAudio = Data()
            accumulatedText  = ""
            state            = .idle
        }
    }

    private func handleTurnComplete() {
        let text  = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let audio = accumulatedAudio

        accumulatedText  = ""
        accumulatedAudio = Data()

        if !audio.isEmpty {
            // Native audio → WAV ойнату (TTS-тен гөрі сапалы)
            playPCMAudio(audio)
        } else if !text.isEmpty {
            // Мәтін жауабы → coordinator TTS арқылы ойнатады
            state = .idle
            onResponse?(text)
        } else {
            state = .idle
            print("ℹ️ GeminiLive: turnComplete, мазмұн жоқ")
        }
    }

    // MARK: - PCM → WAV → AVAudioPlayer

    private func playPCMAudio(_ pcm: Data) {
        let wavData = buildWAV(from: pcm, sampleRate: 24000, channels: 1, bitsPerSample: 16)
        let tmpURL  = FileManager.default.temporaryDirectory
            .appendingPathComponent("gemini_resp_\(Int(Date().timeIntervalSince1970)).wav")

        guard (try? wavData.write(to: tmpURL)) != nil else {
            print("⚠️ GeminiLive: WAV жазу сәтсіз")
            state = .idle
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default,
                                    options: [.duckOthers, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ GeminiLive: аудио сессия (playback) — \(error)")
        }

        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: tmpURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            if audioPlayer?.play() == true {
                state = .speaking
                print("🔊 GeminiLive: ойнатуда — \(pcm.count)б PCM @ 24kHz")
            } else {
                print("⚠️ GeminiLive: play() false")
                state = .idle
            }
        } catch {
            print("⚠️ GeminiLive: AVAudioPlayer — \(error)")
            state = .idle
        }
    }

    /// Raw PCM → WAV (44-байт RIFF header)
    private func buildWAV(from pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var wav = Data()
        let n          = pcm.count
        let byteRate   = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] {
            Array(withUnsafeBytes(of: v.littleEndian) { Array($0) })
        }
        wav += [0x52, 0x49, 0x46, 0x46]; wav += le(UInt32(36 + n))
        wav += [0x57, 0x41, 0x56, 0x45]; wav += [0x66, 0x6D, 0x74, 0x20]
        wav += le(UInt32(16));           wav += le(UInt16(1))
        wav += le(UInt16(channels));     wav += le(UInt32(sampleRate))
        wav += le(UInt32(byteRate));     wav += le(UInt16(blockAlign))
        wav += le(UInt16(bitsPerSample))
        wav += [0x64, 0x61, 0x74, 0x61]; wav += le(UInt32(n))
        wav += pcm
        return wav
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        audioRecorder?.stop()
        audioRecorder = nil
        isConnected   = false
        state         = .disconnected

        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ GeminiLive: max retry жетті")
            return
        }
        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 2.0, 10.0)
        print("🔄 GeminiLive: \(Int(delay))с кейін retry (\(reconnectAttempts)/\(maxReconnectAttempts))")

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.connect() }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension GeminiLiveService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.state == .speaking else { return }
            self.state = .idle
            print("🔊 GeminiLive: аудио аяқталды → idle")
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            print("⚠️ GeminiLive: аудио декод — \(error?.localizedDescription ?? "-")")
            self?.state = .idle
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension GeminiLiveService: URLSessionWebSocketDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("🔌 GeminiLive: WebSocket ашылды")
        Task { @MainActor [weak self] in self?.sendSetup() }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let why = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "-"
        print("🔌 GeminiLive: жабылды — code=\(closeCode.rawValue), reason=\(why)")
        Task { @MainActor [weak self] in self?.scheduleReconnect() }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        print("⚠️ GeminiLive URLSession: \(error.localizedDescription)")
        Task { @MainActor [weak self] in self?.scheduleReconnect() }
    }
}
