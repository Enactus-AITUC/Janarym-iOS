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
    var onTranscription: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var currentRecordingURL: URL?
    private var capturedFrameAtPTTStart: Data?

    private var currentLanguage: UserProfile.Language { OnboardingStore.shared.currentLanguage }
    private var currentPrompt: String { OnboardingStore.shared.assistantPrompt(for: activeMode) }

    func connect() {
        guard state == .disconnected || !isConnected else { return }
        guard !AppConfig.openAIProxyURL.isEmpty else {
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
        if shouldReconnect {
            connect()
        }
    }

    func startPTT(frameJPEG: Data? = nil) {
        clearError()
        capturedFrameAtPTTStart = frameJPEG
        publishTranscription("")
        publishResponseText("")

        if !isConnected {
            connect()
        }

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

    private func beginRecording() {
        let url = makeRecordingURL()
        currentRecordingURL = url

        do {
            try configureRecordingSession()
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
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
            guard !audioData.isEmpty else {
                throw AppError.voiceInputFailed("Audio file is empty")
            }

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

    private func sendAssistRequest(audioData: Data, frameJPEG: Data?) async throws -> AssistResponse {
        guard let url = URL(string: AppConfig.openAIProxyURL) else {
            throw AppError.networkError("Invalid OpenAI proxy URL")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(
            boundary: boundary,
            audioData: audioData,
            frameJPEG: frameJPEG
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.networkError("No HTTP response from proxy")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let message = extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw AppError.networkError(message)
        }

        let decoded = try JSONDecoder().decode(AssistResponseDTO.self, from: data)
        return AssistResponse(
            transcript: decoded.transcript,
            responseText: decoded.responseText,
            audioBase64: decoded.audioBase64
        )
    }

    private func buildMultipartBody(boundary: String, audioData: Data, frameJPEG: Data?) -> Data {
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        func appendField(name: String, value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        func appendFile(name: String, filename: String, mimeType: String, data: Data) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
            append("Content-Type: \(mimeType)\r\n\r\n")
            body.append(data)
            append("\r\n")
        }

        appendField(name: "language", value: currentLanguage.openAITranscriptionLanguageCode)
        appendField(name: "voice", value: AppConfig.openAIVoice)
        appendField(name: "prompt", value: currentPrompt)
        appendField(name: "response_model", value: AppConfig.openAIVisionModel)
        appendField(name: "transcription_model", value: AppConfig.openAITranscriptionModel)
        appendField(name: "tts_model", value: AppConfig.openAITTSModel)
        appendField(name: "mode", value: activeMode.modeKey)
        appendField(name: "speech_rate", value: "\(OnboardingStore.shared.profile.speechRate.avRate)")
        appendFile(name: "audio", filename: "speech.m4a", mimeType: "audio/mp4", data: audioData)

        if let frameJPEG, !frameJPEG.isEmpty {
            appendFile(name: "image", filename: "frame.jpg", mimeType: "image/jpeg", data: frameJPEG)
        }

        append("--\(boundary)--\r\n")
        return body
    }

    @MainActor
    private func playReturnedAudio(base64: String) async throws {
        guard let audioData = Data(base64Encoded: base64) else {
            throw AppError.ttsFailed("Unable to decode returned audio")
        }

        do {
            try configurePlaybackSession()
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            updateConnectionState(.speaking, connected: true)
            if !player.play() {
                throw AppError.ttsFailed("Unable to start playback")
            }
        } catch {
            throw AppError.ttsFailed(error.localizedDescription)
        }
    }

    private func stopRecording() {
        recorder?.stop()
        recorder = nil
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
    }

    private func configureRecordingSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: [.notifyOthersOnDeactivation])
    }

    private func configurePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: [.notifyOthersOnDeactivation])
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("janarym-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }

        return nil
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.onFailure?(message)
        }
    }

    private func clearError() {
        DispatchQueue.main.async {
            self.errorMessage = nil
        }
    }

    private func publishTranscription(_ text: String) {
        DispatchQueue.main.async {
            self.onTranscription?(text)
        }
    }

    private func publishResponseText(_ text: String) {
        DispatchQueue.main.async {
            self.onResponseText?(text)
        }
    }

    private func updateConnectionState(_ newState: OpenAIRealtimeState, connected: Bool) {
        DispatchQueue.main.async {
            self.state = newState
            self.isConnected = connected
        }
    }
}

extension OpenAIRealtimeService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag && state == .recording {
            publishError(AppError.recordingFailed("Recording stopped unexpectedly").localizedDescription)
            updateConnectionState(.idle, connected: true)
        }
    }
}

extension OpenAIRealtimeService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.player = nil
            self.updateConnectionState(.idle, connected: true)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = AppError.ttsFailed(error?.localizedDescription ?? "Audio decode failed").localizedDescription
        publishError(message)
        updateConnectionState(.idle, connected: true)
    }
}

private struct AssistResponseDTO: Decodable {
    let transcript: String
    let responseText: String
    let audioBase64: String?

    enum CodingKeys: String, CodingKey {
        case transcript
        case responseText = "response_text"
        case audioBase64 = "audio_base64"
    }
}

private struct AssistResponse {
    let transcript: String
    let responseText: String
    let audioBase64: String?
}

private extension UserProfile.Language {
    var openAITranscriptionLanguageCode: String {
        self == .kazakh ? "kk" : "ru"
    }
}
