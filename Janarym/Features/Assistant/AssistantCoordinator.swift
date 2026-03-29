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

    // Белсенді режим — UI мен coordinator бірге қолданады
    @Published var activeMode: AppMode = .general {
        didSet { handleModeChange(from: oldValue, to: activeMode) }
    }

    // MARK: - Services

    let cameraService = CameraService()
    let permissionManager = PermissionManager()
    let conversationStore = ConversationStore()
    let locationService = LocationService()
    let sceneWatcher = SceneWatcher()

    // Ауыр объектілер — алғаш қолданғанда ғана жасалады
    private(set) lazy var wakeWordListener = WakeWordListener()
    private(set) lazy var speechRecorder = SpeechRecorder()
    private(set) lazy var ttsService = SpeechSynthesizerService()

    // MARK: - Init

    init() {}

    private var callbacksReady = false
    private var isMainViewVisible = false

    // MARK: - Lifecycle

    func onAppear() {
        permissionManager.checkAll()
        guard permissionManager.allGranted else {
            permissionManager.requestAll()
            return
        }

        activateAssistantIfPossible()
    }

    private func setupSceneWatcher() {
        sceneWatcher.onAlert = { [weak self] alert in
            guard let self else { return }
            // Тек idle режимінде проактивті ескерту беру (speaking/recording кезінде үзбеу)
            guard self.mode == .idle else { return }
            self.ttsService.speak(alert, language: OnboardingStore.shared.profile.language == .kazakh ? .kazakh : .russian)
        }
        sceneWatcher.start(cameraService: cameraService)
    }

    private func ensureCallbacks() {
        guard !callbacksReady else { return }
        callbacksReady = true
        setupCallbacks()
    }

    func onBecameActive() {
        permissionManager.checkAll()
        guard isMainViewVisible, permissionManager.allGranted else { return }
        setupSceneWatcher()
        if !cameraService.isRunning { cameraService.start() }
        if mode == .idle { startWakeListener() }
    }

    func onResignActive() {
        wakeWordListener.stopListening()
        speechRecorder.stopRecording()
        ttsService.stop()
        sceneWatcher.stop()
        if isMainViewVisible {
            cameraService.stop()
        }
    }

    func onPermissionsGranted() {
        permissionManager.checkAll()
        activateAssistantIfPossible()
    }

    func onMainViewAppear() {
        isMainViewVisible = true
        activateAssistantIfPossible()
        startPresenceAndSOS()
    }

    func onMainViewDisappear() {
        isMainViewVisible = false
        wakeWordListener.stopListening()
        speechRecorder.stopRecording()
        ttsService.stop()
        sceneWatcher.stop()
        cameraService.stop()
        SOSManager.shared.stopMonitoring()
        UserPresenceService.shared.stop()
    }

    // MARK: - Presence + SOS

    private func startPresenceAndSOS() {
        guard let uid = AuthServiceHolder.shared.currentUID else { return }
        // Камера кадрын presence фотосы ретінде жүктеу — 5 мин сайын
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

        // Haptic — blind user-ға тактилды растау
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

    private var agentTimer: Timer?

    private func handleModeChange(from old: AppMode, to new: AppMode) {
        if new == .navigation {
            locationService.start()
        } else if old == .navigation {
            locationService.stop()
        }

        // Agent режімі — 4 секунд сайын камерадан автоматты сипаттау
        if new == .agent {
            startAgentLoop()
        } else if old == .agent {
            stopAgentLoop()
        }
    }

    private func startAgentLoop() {
        agentTimer?.invalidate()
        agentTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.mode == .idle, self.activeMode == .agent else { return }
                await self.agentCapture()
            }
        }
    }

    private func stopAgentLoop() {
        agentTimer?.invalidate()
        agentTimer = nil
    }

    private func agentCapture() async {
        let tier = SubscriptionManager.shared.tier
        guard tier.canSendImage else { return }

        let profileLang = OnboardingStore.shared.profile.language
        let language: DetectedLanguage = profileLang == .kazakh ? .kazakh : .russian
        let imageBase64 = cameraService.captureCurrentFrameBase64(maxEdge: CGFloat(tier.imageMaxEdge))
        guard imageBase64 != nil else { return }

        let systemPrompt = language == .kazakh
            ? "Сен нашар көретін адамға нақты уақытта сипаттау жасайсың. Камерадан не көрінсе соны 1-2 сөйлеммен қысқа, нақты айт. Светофор, жол белгілері, адамдар, кедергілер — бәрін атап өт."
            : "Ты делаешь описание в реальном времени для слабовидящего человека. Опиши что видно на камере в 1-2 предложениях. Светофор, знаки, люди, препятствия — указывай всё."

        do {
            mode = .thinking
            let messages: [[String: String]] = [
                ["role": "system", "content": systemPrompt]
            ]
            let response = try await ChatCompletionService.complete(
                messages: messages,
                imageBase64: imageBase64,
                maxTokens: 80,
                imageDetail: "low"
            )
            mode = .speaking
            ttsService.speak(response, language: language)
        } catch {
            mode = .idle
        }
    }

    // MARK: - State machine

    private func transitionTo(_ newMode: AssistantMode) {
        mode = newMode
        errorMessage = nil

        switch newMode {
        case .idle:
            startWakeListener()

        case .wakeDetected:
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.prepare()
            impact.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.transitionTo(.recording)
            }

        case .recording:
            startRecording()

        case .transcribing, .thinking, .speaking:
            break

        case .error:
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.transitionTo(.idle)
            }
        }
    }

    // MARK: - Wake word

    private func startWakeListener() {
        guard isMainViewVisible, callbacksReady, permissionManager.allGranted else { return }
        wakeWordListener.startListening()
    }

    // MARK: - Recording

    private func startRecording() {
        speechRecorder.startRecording()
    }

    // MARK: - Voice Mode Switch

    /// Дауыспен режим ауыстыру — "навигация режимі" деп айтса режимді ауыстырады
    /// API токены жұмсалмайды, true қайтарса pipeline тоқтайды
    private func tryVoiceModeSwitch(text: String, language: DetectedLanguage) -> Bool {
        let lower = text.lowercased()

        // Тек анық режим командасы болса ғана ауыстырамыз (кез келген сөзге емес)
        let modeKeywords: [(AppMode, [String])] = [
            (.general,    ["жалпы режим", "жалпы режімі", "общий режим", "general mode"]),
            (.navigation, ["навигация режимі", "навигация режим", "навигация", "режим навигации"]),
            (.security,   ["қауіпсіздік режимі", "қауіпсіздік режим", "антискам", "режим безопасности", "antiscam"]),
            (.shopping,   ["сауда режимі", "сауда режим", "покупки режим", "режим покупок"]),
            (.reading,    ["мәтін оқу режимі", "мәтін оқу", "оқу режімі", "оқу режим",
                           "чтение режим", "режим чтения"]),
        ]

        for (mode, keywords) in modeKeywords {
            guard keywords.contains(where: { lower.contains($0) }) else { continue }

            let tier = SubscriptionManager.shared.tier
            guard tier.canUseMode(mode.modeKey) else {
                let msg = language == .kazakh
                    ? "Бұл режим жазылым алғандарға ғана қол жетімді."
                    : "Этот режим доступен только по подписке."
                ttsService.speak(msg, language: language)
                transitionTo(.speaking)
                return true
            }

            activeMode = mode
            let modeName: String
            switch language {
            case .kazakh:
                modeName = mode.rawValue
            default:
                switch mode {
                case .general:    modeName = "Общий"
                case .navigation: modeName = "Навигация"
                case .security:   modeName = "Безопасность"
                case .shopping:   modeName = "Покупки"
                case .reading:    modeName = "Чтение"
                case .agent:      modeName = "Агент"
                }
            }
            let msg = language == .kazakh
                ? "\(modeName) режимі қосылды."
                : "Режим \(modeName) активирован."
            ttsService.speak(msg, language: language)
            transitionTo(.speaking)
            return true
        }
        return false
    }

    /// WakeWordListener тікелей мodeKey жіберсе — wake word жоқта да ауыстырады
    private func handleDirectModeSwitch(_ modeKey: String) {
        guard let newMode = AppMode.allCases.first(where: { $0.modeKey == modeKey }) else { return }
        let tier = SubscriptionManager.shared.tier
        let profileLang = OnboardingStore.shared.profile.language
        let language: DetectedLanguage = profileLang == .kazakh ? .kazakh : .russian

        guard tier.canUseMode(modeKey) else {
            let msg = language == .kazakh
                ? "Бұл режим жазылым алғандарға ғана қол жетімді."
                : "Этот режим доступен только по подписке."
            ttsService.speak(msg, language: language)
            return
        }

        activeMode = newMode
        let modeName: String
        switch language {
        case .kazakh:
            modeName = newMode.rawValue
        default:
            switch newMode {
            case .general:    modeName = "Общий"
            case .navigation: modeName = "Навигация"
            case .security:   modeName = "Безопасность"
            case .shopping:   modeName = "Покупки"
            case .reading:    modeName = "Чтение"
            case .agent:      modeName = "Агент"
            }
        }
        let msg = language == .kazakh
            ? "\(modeName) режимі қосылды."
            : "Режим \(modeName) активирован."
        ttsService.speak(msg, language: language)
    }

    // MARK: - Transcription + GPT + TTS pipeline

    private func handleRecordingComplete(fileURL: URL) {
        transitionTo(.transcribing)

        Task {
            do {
                let result = try await WhisperTranscriptionService.transcribe(fileURL: fileURL)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !text.isEmpty else {
                    transitionTo(.idle)
                    return
                }

                lastTranscription = text
                let profileLang = OnboardingStore.shared.profile.language
                let language: DetectedLanguage = profileLang == .kazakh ? .kazakh : .russian

                // Дауыспен SOS — ең жоғары приоритет
                if SOSManager.containsSOSCommand(text) {
                    triggerSOS()
                    transitionTo(.idle)
                    return
                }

                // Дауыспен режим ауыстыру — API токены жұмсамайды
                if tryVoiceModeSwitch(text: text, language: language) {
                    return
                }

                // Subscription check — лимит тексеру
                let sub = SubscriptionManager.shared
                let tier = sub.tier

                guard sub.canMakeRequest else {
                    let msg = profileLang == .kazakh
                        ? "Бүгінгі сұрақтар аяқталды. Жазылым алу үшін қосымшаны ашыңыз."
                        : "Запросы на сегодня исчерпаны. Оформите подписку в приложении."
                    ttsService.speak(msg, language: language)
                    transitionTo(.idle)
                    return
                }
                sub.recordRequest()

                // Memory — тек VIP
                if tier.canUseMemory {
                    if let toForget = MemoryStore.shared.extractForgetIntent(from: text) {
                        MemoryStore.shared.remove(containing: toForget)
                        let reply = profileLang == .kazakh ? "Жадтан өшірдім." : "Удалил из памяти."
                        conversationStore.addAssistant(reply)
                        transitionTo(.speaking)
                        ttsService.speak(reply, language: language)
                        return
                    }
                    if let toRemember = MemoryStore.shared.extractMemoryIntent(from: text) {
                        MemoryStore.shared.add(toRemember)
                        let reply = profileLang == .kazakh ? "Есімде сақтадым." : "Запомнил."
                        conversationStore.addAssistant(reply)
                        transitionTo(.speaking)
                        ttsService.speak(reply, language: language)
                        return
                    }
                }

                conversationStore.addUser(text)
                transitionTo(.thinking)

                // Камера суреті — tier-ге байланысты
                let imageBase64: String? = tier.canSendImage
                    ? cameraService.captureCurrentFrameBase64(maxEdge: CGFloat(tier.imageMaxEdge))
                    : nil  // Free → сурет жібермейді = 0 token

                // Навигация — тек VIP
                var navContext: String? = nil
                if activeMode == .navigation && tier.canUseMode("navigation") {
                    navContext = await buildNavigationContext(for: text)
                }

                let messages = conversationStore.messagesForAPI(
                    navigationContext: navContext,
                    activeMode: activeMode,
                    maxMessages: tier.maxConversationMessages
                )
                let response = try await ChatCompletionService.complete(
                    messages: messages,
                    imageBase64: imageBase64,
                    maxTokens: tier.maxResponseTokens,
                    imageDetail: tier.imageDetail
                )

                lastResponse = response
                conversationStore.addAssistant(response)

                transitionTo(.speaking)
                ttsService.speak(response, language: language)

            } catch {
                errorMessage = error.localizedDescription
                transitionTo(.error)
            }
        }
    }

    // MARK: - Navigation context builder

    private func buildNavigationContext(for text: String) async -> String {
        var parts: [String] = []

        // Орналасу мекенжайы
        let locCtx = locationService.locationContext
        if !locCtx.isEmpty { parts.append(locCtx) }

        let lowered = text.lowercased()

        // Маршрут сұрады ма?
        let routeKeywords = ["жеткіз", "жету", "маршрут", "жол", "баруым", "бару керек",
                             "қалай барамын", "доведи", "как дойти", "маршрут до"]
        if routeKeywords.contains(where: { lowered.contains($0) }) {
            let routeResult = await locationService.buildWalkingRoute(to: text)
            parts.append("Маршрут нәтижесі:\n\(routeResult)")
        }

        // Жақын жер сұрады ма?
        let nearbyKeywords = ["жақын", "маңайдағы", "жанындағы", "қайда бар",
                              "рядом", "поблизости", "ближайший"]
        if nearbyKeywords.contains(where: { lowered.contains($0) }) {
            let nearbyResult = await locationService.searchNearby(text)
            parts.append("Жақын жерлер:\n\(nearbyResult)")
        }

        return parts.isEmpty ? "" : parts.joined(separator: "\n\n")
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        wakeWordListener.onWakeWordDetected = { [weak self] in
            DispatchQueue.main.async {
                self?.wakeWordListener.stopListening()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.transitionTo(.wakeDetected)
                }
            }
        }

        wakeWordListener.onModeCommandDetected = { [weak self] modeKey in
            DispatchQueue.main.async {
                self?.handleDirectModeSwitch(modeKey)
            }
        }

        speechRecorder.onRecordingComplete = { [weak self] url in
            DispatchQueue.main.async {
                self?.handleRecordingComplete(fileURL: url)
            }
        }

        ttsService.onFinished = { [weak self] in
            DispatchQueue.main.async {
                self?.transitionTo(.idle)
            }
        }
    }

    private func activateAssistantIfPossible() {
        guard isMainViewVisible, permissionManager.allGranted else { return }

        ensureCallbacks()
        setupSceneWatcher()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isMainViewVisible, self.permissionManager.allGranted else { return }
            self.cameraService.start()
        }

        transitionTo(.idle)
    }
}
