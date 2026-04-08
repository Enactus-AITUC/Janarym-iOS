import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class AssistantCoordinator: ObservableObject {

    // MARK: - Published state

    @Published var mode: AssistantMode = .idle
    @Published var lastTranscription: String = ""
    @Published var lastResponse: String = ""
    @Published var errorMessage: String?

    @Published var activeMode: AppMode = .general {
        didSet { handleModeChange(from: oldValue, to: activeMode) }
    }

    // MARK: - Services

    let cameraService    = CameraService()
    let permissionManager = PermissionManager()
    let locationService  = LocationService()
    let geminiService    = GeminiLiveService()
    private(set) lazy var ttsService = SpeechSynthesizerService()

    // MARK: - Private

    private var isMainViewVisible = false
    private var callbacksReady = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {}

    // MARK: - Lifecycle

    func onAppear() {
        permissionManager.checkAll()
        if !permissionManager.allGranted {
            permissionManager.requestAll()
        }
        activateAssistantIfPossible()
    }

    func onBecameActive() {
        permissionManager.checkAll()
        guard isMainViewVisible else { return }
        if !cameraService.isRunning { cameraService.start() }
    }

    func onResignActive() {
        ttsService.stop()
        if isMainViewVisible { cameraService.stop() }
    }

    func onPermissionsGranted() {
        permissionManager.checkAll()
        guard isMainViewVisible, permissionManager.allGranted else { return }
    }

    func onMainViewAppear() {
        isMainViewVisible = true
        if !permissionManager.allGranted {
            permissionManager.requestAll()
        }
        activateAssistantIfPossible()
        startPresenceAndSOS()
    }

    func onMainViewDisappear() {
        isMainViewVisible = false
        ttsService.stop()
        cameraService.stop()
        geminiService.disconnect()
        SOSManager.shared.stopMonitoring()
        UserPresenceService.shared.stop()
    }

    // MARK: - PTT (Push-to-Talk)

    func startPTT() {
        ttsService.stop()
        mode = .recording
        let frameJPEG = cameraService.captureCurrentFrameJPEG(maxEdge: 1024)
        geminiService.startPTT(frameJPEG: frameJPEG)
    }

    func stopPTT() {
        mode = .processing
        geminiService.stopPTTAndSend(cameraService: cameraService)

        // 10 секунд ішінде жауап болмаса — idle-ге қайту
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, self.mode == .processing else { return }
            self.mode = .idle
        }
    }

    // MARK: - Presence + SOS

    private func startPresenceAndSOS() {
        guard AppConfig.presenceMonitoringEnabled else { return }
        guard let uid = AuthServiceHolder.shared.currentUID else { return }
        UserPresenceService.shared.capturePhoto = { [weak self] in
            self?.cameraService.captureCurrentFrameJPEG(maxEdge: 512)
        }
        UserPresenceService.shared.start(userId: uid)

        SOSManager.shared.startMonitoring()
        SOSManager.shared.onSOS = { [weak self] in
            self?.triggerSOS()
        }
    }

    func triggerSOS() {
        let profileLang = OnboardingStore.shared.profile.language
        let language: DetectedLanguage = profileLang == .kazakh ? .kazakh : .russian
        let msg = language == .kazakh
            ? "SOS жіберілді. Ата-анаңызға хабар кетті."
            : "SOS отправлен. Родитель получил уведомление."

        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.warning)

        ttsService.speak(msg, language: language)

        guard let uid = AuthServiceHolder.shared.currentUID else { return }
        let loc = UserPresenceService.shared.lastLocation
        Task {
            await FirestoreService.shared.triggerSOS(
                userId: uid,
                lat: loc?.coordinate.latitude ?? 0,
                lng: loc?.coordinate.longitude ?? 0
            )
        }
    }

    // MARK: - Mode change

    private func handleModeChange(from old: AppMode, to new: AppMode) {
        if new == .navigation {
            locationService.start()
        } else if old == .navigation {
            locationService.stop()
        }
    }

    // MARK: - Private helpers

    private func activateAssistantIfPossible() {
        guard isMainViewVisible else { return }

        ensureCallbacks()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isMainViewVisible else { return }
            if !self.cameraService.isRunning { self.cameraService.start() }
        }

        guard permissionManager.allGranted else { return }
        mode = .idle
    }

    private func ensureCallbacks() {
        guard !callbacksReady else { return }
        callbacksReady = true

        // onResponse — тек мәтін жауап болғанда (аудио болмаса fallback TTS)
        // Аудио жауап GeminiLiveService-те тікелей ойнатылады
        geminiService.onResponse = { [weak self] text in
            guard let self else { return }
            self.lastResponse = text
            self.mode = .speaking
            let lang = OnboardingStore.shared.profile.language == .kazakh
                ? DetectedLanguage.kazakh : .russian
            self.ttsService.speak(text, language: lang)
        }

        geminiService.onTranscription = { [weak self] text in
            self?.lastTranscription = text
        }

        geminiService.onFailure = { [weak self] message in
            guard let self else { return }
            self.errorMessage = message
            self.lastResponse = message
            self.mode = .error
        }

        ttsService.onFinished = { [weak self] in
            self?.mode = .idle
        }

        // GeminiLiveService.state → AssistantMode синхрондау
        geminiService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] geminiState in
                guard let self else { return }
                switch geminiState {
                case .idle:
                    if self.mode == .processing || self.mode == .recording || self.mode == .speaking {
                        self.mode = .idle
                    }
                case .recording:
                    self.mode = .recording
                case .processing:
                    self.mode = .processing
                case .speaking:
                    self.mode = .speaking
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
}
