import AVFoundation
import Foundation

private func print(_ items: Any...) {}

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
// Model: AppConfig.geminiLiveModel
// Input:  audio/pcm;rate=16000 (16-bit, mono PCM)
// Output: audio/pcm (24kHz, 16-bit, mono PCM) → WAV → AVAudioPlayer

@MainActor
final class GeminiLiveService: NSObject, ObservableObject {

    @Published var state: GeminiLiveState = .disconnected
    @Published var isConnected = false
    @Published var errorMessage: String?

    /// Мәтін жауабы болса шақырылады (TTS fallback)
    var onResponse: ((String) -> Void)?
    var onTranscription: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var capturedFrameAtPTTStart: Data?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    private var accumulatedText  = ""
    private var accumulatedAudio = Data()

    private var audioPlayer: AVAudioPlayer?

    private let wsBase = "wss://generativelanguage.googleapis.com/ws/"
        + "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    private let model  = AppConfig.geminiLiveModel

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
                "thinking_config": [
                    "thinking_level": "minimal"
                ],
                "realtime_input_config": [
                    "automatic_activity_detection": [
                        "disabled": true
                    ],
                    "turn_coverage": "TURN_INCLUDES_AUDIO_ACTIVITY_AND_ALL_VIDEO"
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

    func startPTT(frameJPEG: Data? = nil) {
        print("🎙️ GeminiLive: startPTT — state=\(state)")
        guard state == .idle || state == .disconnected else { return }

        capturedFrameAtPTTStart = frameJPEG
        if let frameJPEG {
            print("📸 GeminiLive: кадр бекітілді — jpeg=\(frameJPEG.count) байт")
        } else {
            print("⚠️ GeminiLive: PTT басында кадр жоқ")
        }
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
        AudioSessionManager.configure()

        state            = .processing
        accumulatedText  = ""
        accumulatedAudio = Data()
        errorMessage     = nil

        guard let audioURL = recordingURL else { state = .idle; return }
        let imageData = capturedFrameAtPTTStart ?? cameraService.captureCurrentFrameJPEG(maxEdge: 1024)
        capturedFrameAtPTTStart = nil
        Task { await requestSceneAnswer(audioURL: audioURL, imageData: imageData) }
    }

    // MARK: - Scene request

    private func requestSceneAnswer(audioURL: URL, imageData: Data?) async {
        guard let wavData = try? Data(contentsOf: audioURL),
              wavData.count > 44 else {
            print("⚠️ GeminiLive: аудио бос")
            state = .idle
            return
        }

        guard !AppConfig.geminiAPIKey.isEmpty else {
            errorMessage = "API key жоқ"
            state = .idle
            return
        }

        let transcript = await transcribeAudio(wavData: wavData)
        let normalizedTranscript = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        print("📝 Gemini STT: \(normalizedTranscript.prefix(160))")
        if !normalizedTranscript.isEmpty {
            onTranscription?(normalizedTranscript)
        }

        var parts: [[String: Any]] = [[
            "text": """
            Interpret the user's spoken question from the attached audio.
            Use the attached image as the primary source of truth for what is visible.
            Reply in the same language the user speaks, especially Kazakh or Russian.
            If the user asks what is ahead, what is in front, or what they see, mention only 2 to 5 concrete visible objects or obstacles directly in front of them.
            Do not give abstract advice, guesses, motivational phrases, colors, shapes, or extra details.
            If the frame is unclear, briefly say that the frame is unclear.
            Keep the answer short and natural for TTS.
            """
        ]]

        parts.append([
            "inline_data": [
                "mime_type": "audio/wav",
                "data": wavData.base64EncodedString()
            ]
        ])

        if let imageData, !imageData.isEmpty {
            print("📤 GeminiLive fallback: кадр жіберілуде — jpeg=\(imageData.count) байт")
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ])
        } else {
            print("⚠️ GeminiLive fallback: кадр жоқ")
        }

        if !normalizedTranscript.isEmpty {
            parts.append([
                "text": "Possible transcription hint only if useful: \(normalizedTranscript)"
            ])
        } else {
            parts.append([
                "text": "The local transcription was unavailable. Infer the question from the audio instead."
            ])
        }

        let payload: [String: Any] = [
            "system_instruction": [
                "parts": [["text": AppConfig.systemPrompt]]
            ],
            "contents": [[
                "role": "user",
                "parts": parts
            ]],
            "generationConfig": [
                "temperature": 0.2,
                "top_p": 0.8,
                "max_output_tokens": 128,
                "responseMimeType": "text/plain"
            ]
        ]

        guard let url = URL(string: "\(AppConfig.geminiBaseURL)/v1beta/models/\(AppConfig.geminiChatModel):generateContent"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            state = .idle
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 45
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "HTTP жауап жоқ"
                state = .idle
                return
            }

            if !(200...299).contains(http.statusCode) {
                let raw = String(data: data, encoding: .utf8) ?? "unknown"
                print("❌ Gemini fallback HTTP \(http.statusCode): \(raw.prefix(300))")
                let message = extractAPIErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                errorMessage = message
                onFailure?(message)
                state = .idle
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let message = "Жауапты оқу сәтсіз"
                print("❌ Gemini fallback: жауап парсингі сәтсіз")
                errorMessage = message
                onFailure?(message)
                state = .idle
                return
            }

            if let promptFeedback = json["promptFeedback"] as? [String: Any],
               let blockReason = promptFeedback["blockReason"] as? String {
                let message = "Gemini block: \(blockReason)"
                print("❌ Gemini fallback: \(message)")
                errorMessage = message
                onFailure?(message)
                state = .idle
                return
            }

            guard
                let candidates = json["candidates"] as? [[String: Any]],
                let first = candidates.first,
                let content = first["content"] as? [String: Any],
                let responseParts = content["parts"] as? [[String: Any]]
            else {
                let message = "Gemini бос жауап берді"
                print("❌ Gemini fallback: кандидаттар жоқ")
                errorMessage = message
                onFailure?(message)
                state = .idle
                return
            }

            let text = responseParts
                .compactMap { $0["text"] as? String }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                let message = normalizedTranscript.isEmpty
                    ? "Жауап жоқ. Суретті анық көрінетіндей етіп қайта сұрап көріңіз."
                    : "Жауап жоқ. Қысқа сұрақпен қайта айтып көріңіз."
                print("⚠️ Gemini fallback: бос жауап")
                errorMessage = message
                onFailure?(message)
                state = .idle
                return
            }

            print("✅ Gemini fallback: \(text.prefix(160))")
            state = .idle
            onResponse?(text)
        } catch {
            print("❌ Gemini fallback network: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            onFailure?(error.localizedDescription)
            state = .idle
        }
    }

    private func extractAPIErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any]
        else { return nil }

        if let message = error["message"] as? String, !message.isEmpty {
            return message
        }

        return nil
    }

    private func transcribeAudio(wavData: Data) async -> String? {
        let payload: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    [
                        "text": """
                        Generate an exact transcript of the user's speech from the attached audio.
                        Keep the original spoken language.
                        Prioritize Kazakh and Russian.
                        Return only the transcript text with no commentary.
                        """
                    ],
                    [
                        "inline_data": [
                            "mime_type": "audio/wav",
                            "data": wavData.base64EncodedString()
                        ]
                    ]
                ]
            ]],
            "generationConfig": [
                "temperature": 0,
                "top_p": 0.1,
                "max_output_tokens": 96,
                "responseMimeType": "text/plain"
            ]
        ]

        guard let url = URL(string: "\(AppConfig.geminiBaseURL)/v1beta/models/\(AppConfig.geminiChatModel):generateContent"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let candidates = json["candidates"] as? [[String: Any]],
                let first = candidates.first,
                let content = first["content"] as? [String: Any],
                let parts = content["parts"] as? [[String: Any]]
            else {
                return nil
            }

            let text = parts
                .compactMap { $0["text"] as? String }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return text.isEmpty ? nil : text
        } catch {
            print("⚠️ Gemini STT network: \(error.localizedDescription)")
            return nil
        }
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

    private func extractPCM(fromWAV wavData: Data) -> Data? {
        guard wavData.count > 44 else { return nil }

        let header = Data([0x52, 0x49, 0x46, 0x46]) // RIFF
        let wave = Data([0x57, 0x41, 0x56, 0x45])   // WAVE
        guard wavData.prefix(4) == header,
              wavData.dropFirst(8).prefix(4) == wave else {
            return nil
        }

        var offset = 12
        while offset + 8 <= wavData.count {
            let chunkID = wavData.subdata(in: offset ..< offset + 4)
            let chunkSizeData = wavData.subdata(in: offset + 4 ..< offset + 8)
            let chunkSize = chunkSizeData.withUnsafeBytes { rawBuffer in
                rawBuffer.load(as: UInt32.self).littleEndian
            }

            let dataStart = offset + 8
            let dataEnd = dataStart + Int(chunkSize)
            guard dataEnd <= wavData.count else { return nil }

            if chunkID == Data([0x64, 0x61, 0x74, 0x61]) { // data
                return wavData.subdata(in: dataStart ..< dataEnd)
            }

            offset = dataEnd + (Int(chunkSize) % 2)
        }

        return nil
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
