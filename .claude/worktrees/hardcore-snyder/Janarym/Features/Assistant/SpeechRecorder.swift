import AVFoundation
import Combine

final class SpeechRecorder: NSObject, ObservableObject {

    @Published var isRecording = false

    var onRecordingComplete: ((URL) -> Void)?

    private var audioRecorder: AVAudioRecorder?
    private var silenceTimer: Timer?
    private var maxDurationTimer: Timer?
    private var meteringTimer: Timer?
    private var speechDetected = false

    private var fileURL: URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("janarym_command.wav")
    }

    func startRecording() {
        guard !isRecording else { return }

        // Audio session is managed globally by AudioSessionManager — no reconfiguration needed

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.delegate = self
            audioRecorder?.record()
            isRecording = true
            speechDetected = false
            startMonitoring()
        } catch {
            print("SpeechRecorder: recorder error: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        cancelTimers()
        audioRecorder?.stop()
        isRecording = false
    }

    // MARK: - Silence detection

    private func startMonitoring() {
        // Metering check every 100ms
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkMetering()
        }

        // Absolute max duration
        maxDurationTimer = Timer.scheduledTimer(
            withTimeInterval: AppConfig.maxRecordingDuration,
            repeats: false
        ) { [weak self] _ in
            self?.finishRecording()
        }
    }

    private var silenceStart: Date?

    private func checkMetering() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)

        if power > AppConfig.silenceThreshold {
            // Sound detected
            speechDetected = true
            silenceStart = nil
        } else if speechDetected {
            // Silence after speech
            if silenceStart == nil {
                silenceStart = Date()
            } else if let start = silenceStart,
                      Date().timeIntervalSince(start) >= AppConfig.silenceDuration {
                finishRecording()
            }
        }
    }

    private func finishRecording() {
        guard isRecording else { return }
        cancelTimers()
        audioRecorder?.stop()
        isRecording = false
        onRecordingComplete?(fileURL)
    }

    private func cancelTimers() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        silenceStart = nil
    }
}

extension SpeechRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("SpeechRecorder: recording finished unsuccessfully")
        }
    }
}
