import AVFoundation
import Foundation

enum OpenAIRealtimeState: Equatable {
    case disconnected
    case connecting
    case idle
    case recording
    case processing
    case speaking
}

final class OpenAIRealtimeService: NSObject, ObservableObject {

    @Published private(set) var state: OpenAIRealtimeState = .disconnected
    @Published private(set) var isConnected = false
    @Published var errorMessage: String?

    var activeMode: AppMode = .general
    var onResponseText: ((String) -> Void)?
    var onTranscription:  ((String) -> Void)?
    var onFailure:        ((String) -> Void)?

    private var recorder: AVAudioRecorder?
    private var player:   AVAudioPlayer?
    private var currentRecordingURL: URL?
    private var capturedFrameAtPTTStart: Data?

    private var currentLanguage: UserProfile.Language { OnboardingStore.shared.currentLanguage }
    private var currentPrompt:   String               { OnboardingStore.shared.assistantPrompt(for: activeMode) }

    // MARK: - Mode

    /// true  → proxy mode (OPENAI_PROXY_URL set)
    /// false → direct mode (OPENAI_API_KEY only)
    private var useProxy: Bool { !AppConfig.openAIProxyURL.isEmpty }

    // MARK: - Lifecycle

    func connect() {
        guard state == .disconnected || !isConnected else { return }
        guard useProxy || !AppConfig.openAIAPIKey.isEmpty else {
            publishError(AppError.missingAPIKey.localizedDescription)
            return
        }
        clearError()
        updateConnectionState(.idle, connected: true)
    }

    func disconnect() {
        stopRecording()
        stopPlayback()
        currentRecordingURL = nil
        capturedFrameAtPTTStart = nil
        updateConnectionState(.disconnected, connected: false)
    }

    func handleLanguageChange() {
        let shouldReconnect = isConnected
        disconnect()
        publishTranscription("")
        publishResponseText("")
        if shouldReconnect { connect() }
    }

    func startPTT(frameJPEG: Data? = nil) {
        clearError()
        capturedFrameAtPTTStart = frameJPEG
        publishTranscription("")
        publishResponseText("")
        if !isConnected { connect() }
        guard isConnected || state == .idle else { return }
        stopPlayback()
        beginRecording()
    }

    func stopPTTAndRespond(frameJPEG: Data? = nil) {
        guard state == .recording else { return }
        updateConnectionState(.processing, connected: true)
        let responseFrame = frameJPEG ?? capturedFrameAtPTTStart
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            await self?.finishTurn(frameJPEG: responseFrame)
        }
    }

    // MARK: - Recording

    private func beginRecording() {
        let url = makeRecordingURL()
        currentRecordingURL = url
        do {
            try configureRecordingSession()
            let settings: [String: Any] = [
                AVFormatIDKey:            Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey:          44_100,
                AVNumberOfChannelsKey:    1,
                AVEncoderBitRateKey:      64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = false
            recorder.prepareToRecord()
            guard recorder.record(forDuration: AppConfig.maxRecordingDuration) else {
                throw AppError.recordingFailed("Unable to start the recorder")
            }
            self.recorder = recorder
            updateConnectionState(.recording, connected: true)
        } catch {
            publishError(AppError.recordingFailed(error.localizedDescription).localizedDescription)
            updateConnectionState(.idle, connected: true)
        }
    }

    private func finishTurn(frameJPEG: Data?) async {
        stopRecording()
        guard let url = currentRecordingURL else {
            publishError(AppError.voiceInputFailed("Audio file is missing").localizedDescription)
            updateConnectionState(.idle, connected: true)
            return
        }
        do {
            let audioData = try Data(contentsOf: url)
            guard !audioData.isEmpty else { throw AppError.voiceInputFailed("Audio file is empty") }

            let response = try await sendAssistRequest(audioData: audioData, frameJPEG: frameJPEG)
            publishTranscription(response.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
            publishResponseText(response.responseText.trimmingCharacters(in: .whitespacesAndNewlines))

            if let audioBase64 = response.audioBase64, !audioBase64.isEmpty {
                try await playReturnedAudio(base64: audioBase64)
            } else {
                updateConnectionState(.idle, connected: true)
            }
        } catch {
            publishError(error.localizedDescription)
            updateConnectionState(.idle, connected: true)
        }
    }

    // MARK: - Request routing

    private func sendAssistRequest(audioData: Data, frameJPEG: Data?) async throws -> AssistResponse {
        if useProxy {
            return try await sendViaProxy(audioData: audioData, frameJPEG: frameJPEG)
        } else {
            return try await sendDirect(audioData: audioData, frameJPEG: frameJPEG)
        }
    }

    // MARK: - Proxy mode

    private func sendViaProxy(audioData: Data, frameJPEG: Data?) async throws -> AssistResponse {
        guard let url = URL(string: AppConfig.openAIProxyURL) else {
            throw AppError.networkError("Invalid OpenAI proxy URL")
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(boundary: boundary, audioData: audioData, frameJPEG: frameJPEG)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.networkError("No HTTP response from proxy")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.networkError(extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)")
        }
        let dto = try JSONDecoder().decode(AssistResponseDTO.self, from: data)
        return AssistResponse(transcript: dto.transcript, responseText: dto.responseText, audioBase64: dto.audioBase64)
    }

    // MARK: - Direct mode (Whisper → GPT → TTS)

    private func sendDirect(audioData: Data, frameJPEG: Data?) async throws -> AssistResponse {
        let apiKey = AppConfig.openAIAPIKey

        // Step 1 — Transcribe audio with Whisper
        let transcript = try await transcribeAudio(audioData, apiKey: apiKey)

        // Step 2 — Get GPT response (+ optional camera frame)
        let responseText = try await getChatResponse(
            transcript: transcript,
            frameJPEG: frameJPEG,
            apiKey: apiKey
        )

        // Step 3 — Synthesise speech
        let audioBase64 = try? await synthesiseSpeech(text: responseText, apiKey: apiKey)

        return AssistResponse(transcript: transcript, responseText: responseText, audioBase64: audioBase64)
    }

    // Step 1: Whisper transcription
    private func transcribeAudio(_ audioData: Data, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            throw AppError.networkError("Invalid transcription URL")
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(AppConfig.openAITranscriptionModel)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n\(currentLanguage.openAITranscriptionLanguageCode)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n")
        body.append(audioData)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppError.voiceInputFailed(extractErrorMessage(from: data) ?? "Transcription failed")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["text"] as? String
        else { throw AppError.voiceInputFailed("Unexpected transcription response") }
        return text
    }

    // Step 2: GPT-4.1 vision chat
    private func getChatResponse(transcript: String, frameJPEG: Data?, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw AppError.networkError("Invalid chat URL")
        }
        var userContent: [[String: Any]] = [["type": "text", "text": transcript]]
        if let jpg = frameJPEG, !jpg.isEmpty {
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(jpg.base64EncodedString())", "detail": "low"]
            ])
        }
        let payload: [String: Any] = [
            "model": AppConfig.openAIVisionModel,
            "max_tokens": 300,
            "messages": [
                ["role": "system", "content": currentPrompt],
                ["role": "user",   "content": userContent]
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppError.assistantResponseFailed(extractErrorMessage(from: data) ?? "Chat failed")
        }
        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw AppError.assistantResponseFailed("Unexpected chat response") }
        return content
    }

    // Step 3: TTS speech synthesis
    private func synthesiseSpeech(text: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            throw AppError.ttsFailed("Invalid TTS URL")
        }
        let payload: [String: Any] = [
            "model": AppConfig.openAITTSModel,
            "input": text,
            "voice": AppConfig.openAIVoice,
            "response_format": "mp3",
            "speed": OnboardingStore.shared.profile.speechRate.avRate
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppError.ttsFailed(extractErrorMessage(from: data) ?? "TTS failed")
        }
        return data.base64EncodedString()
    }

    // MARK: - Multipart body (proxy mode)

    private func buildMultipartBody(boundary: String, audioData: Data, frameJPEG: Data?) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        func file(_ name: String, _ filename: String, _ mime: String, _ data: Data) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n")
            body.append(data)
            append("\r\n")
        }
        field("language",            currentLanguage.openAITranscriptionLanguageCode)
        field("voice",               AppConfig.openAIVoice)
        field("prompt",              currentPrompt)
        field("response_model",      AppConfig.openAIVisionModel)
        field("transcription_model", AppConfig.openAITranscriptionModel)
        field("tts_model",           AppConfig.openAITTSModel)
        field("mode",                activeMode.modeKey)
        field("speech_rate",         "\(OnboardingStore.shared.profile.speechRate.avRate)")
        file("audio", "speech.m4a", "audio/mp4", audioData)
        if let jpg = frameJPEG, !jpg.isEmpty { file("image", "frame.jpg", "image/jpeg", jpg) }
        append("--\(boundary)--\r\n")
        return body
    }

    // MARK: - Playback

    @MainActor
    private func playReturnedAudio(base64: String) async throws {
        guard let audioData = Data(base64Encoded: base64) else {
            throw AppError.ttsFailed("Unable to decode returned audio")
        }
        try configurePlaybackSession()
        let player = try AVAudioPlayer(data: audioData)
        player.delegate = self
        player.prepareToPlay()
        self.player = player
        updateConnectionState(.speaking, connected: true)
        guard player.play() else { throw AppError.ttsFailed("Unable to start playback") }
    }

    // MARK: - Audio session helpers

    private func stopRecording() { recorder?.stop(); recorder = nil }
    private func stopPlayback()  { player?.stop();   player  = nil }

    private func configureRecordingSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try s.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func configurePlaybackSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try s.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("janarym-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }

    // MARK: - Helpers

    private func extractErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = json["error"] as? [String: Any], let msg = err["message"] as? String, !msg.isEmpty { return msg }
            if let msg = json["message"] as? String, !msg.isEmpty { return msg }
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async { self.errorMessage = message; self.onFailure?(message) }
    }
    private func clearError() {
        DispatchQueue.main.async { self.errorMessage = nil }
    }
    private func publishTranscription(_ text: String) {
        DispatchQueue.main.async { self.onTranscription?(text) }
    }
    private func publishResponseText(_ text: String) {
        DispatchQueue.main.async { self.onResponseText?(text) }
    }
    private func updateConnectionState(_ newState: OpenAIRealtimeState, connected: Bool) {
        DispatchQueue.main.async { self.state = newState; self.isConnected = connected }
    }
}

// MARK: - AVAudio delegates

extension OpenAIRealtimeService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag && state == .recording {
            publishError(AppError.recordingFailed("Recording stopped unexpectedly").localizedDescription)
            updateConnectionState(.idle, connected: true)
        }
    }
}

extension OpenAIRealtimeService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        DispatchQueue.main.async { self.player = nil; self.updateConnectionState(.idle, connected: true) }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        publishError(AppError.ttsFailed(error?.localizedDescription ?? "Audio decode failed").localizedDescription)
        updateConnectionState(.idle, connected: true)
    }
}

// MARK: - Private models

private struct AssistResponseDTO: Decodable {
    let transcript:   String
    let responseText: String
    let audioBase64:  String?
    enum CodingKeys: String, CodingKey {
        case transcript
        case responseText = "response_text"
        case audioBase64  = "audio_base64"
    }
}

private struct AssistResponse {
    let transcript:   String
    let responseText: String
    let audioBase64:  String?
}

private extension UserProfile.Language {
    var openAITranscriptionLanguageCode: String { self == .kazakh ? "kk" : "ru" }
}
