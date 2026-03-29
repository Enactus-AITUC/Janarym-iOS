import Foundation

// MARK: - SceneWatcher
// Әр 30 секунд сайын камерадан кадр алып GPT-ға жіберіп,
// шынымен маңызды нәрсе болса ғана айтады (проактивті, API-тиімді)

@MainActor
final class SceneWatcher {

    var onAlert: ((String) -> Void)?

    private var isRunning = false
    private var watchTask: Task<Void, Never>?
    private let intervalSeconds: Double = 60.0  // 60 сек — API шығынын максималды азайту

    // GPT "жоқ нәрсе жоқ" деп жазып жіберетін фраза-сүзгілер
    private let noisePatterns = [
        "бос", "ештеңе", "маңызды емес", "байқалмады", "жоқ нәрсе",
        "пусто", "ничего", "нет ничего", "не обнурежено", "всё в порядке",
        "nothing", "no danger", "clear", "ok", "okey", "safe",
        "пустой", "empty", "не вижу ничего важного", "маңызды нәрсе байқалмады"
    ]

    // MARK: - Lifecycle

    func start(cameraService: CameraService) {
        guard !isRunning else { return }
        isRunning = true
        watchTask = Task { [weak self] in
            // Алғашқы тексеруді 10 сек кейін бастау (app жүктелуін күту)
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await self?.watchLoop(cameraService: cameraService)
        }
    }

    func stop() {
        isRunning = false
        watchTask?.cancel()
        watchTask = nil
    }

    // MARK: - Watch loop

    private func watchLoop(cameraService: CameraService) async {
        while isRunning && !Task.isCancelled {
            await checkScene(cameraService: cameraService)
            try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
        }
    }

    private func checkScene(cameraService: CameraService) async {
        // SceneWatcher тек VIP үшін — API шығынын максималды азайту
        guard SubscriptionManager.shared.tier.canUseSceneWatcher else { return }

        guard let base64 = cameraService.captureCurrentFrameBase64(),
              !Task.isCancelled else { return }

        let kk = OnboardingStore.shared.profile.language == .kazakh

        // Промпт: GPT-ға "ешнәрсе жазба" деп нақты айту — бос string қайтарсын
        let watchPrompt = kk ? """
Сен нашар көретін адамның AI көзісің. Суретті талда.
Егер ШЫНЫМЕН маңызды нәрсе болса — БІР ҒАНА қысқа сөйлеммен айт:
• Қауіп: баспалдақ, жол, автокөлік, кедергі, шұңқыр
• Адам: жақындап келеді немесе сөйлесуге тырысады
• Маңызды мәтін: ескерту, қауіп белгісі
• Ақша, маңызды құжат

Маңызды емес нәрсе (кеңсе, бөлме, қарапайым заттар) — ештеңе жазба, жауапты МҮЛДЕ БОС қалдыр.
""" : """
Ты — AI-глаза для слабовидящего. Проанализируй изображение.
Только если видишь РЕАЛЬНУЮ опасность или важное — напиши ОДНО короткое предложение:
• Опасность: ступеньки, дорога, машина, препятствие, яма
• Человек: подходит или пытается заговорить
• Важный текст: предупреждение, знак опасности
• Деньги, важный документ

Обычная обстановка (офис, комната, мебель) — не пиши НИЧЕГО, оставь ответ ПОЛНОСТЬЮ ПУСТЫМ.
"""

        // "low" detail = 85 fixed tokens (vs "auto" = 800-30K tokens)
        // 384px сурет + low detail = ~100 tokens/request
        let smallBase64 = cameraService.captureCurrentFrameBase64(maxEdge: 384) ?? base64

        let result = try? await ChatCompletionService.complete(
            messages: [
                ["role": "system", "content": watchPrompt],
                ["role": "user", "content": "Тексер."]
            ],
            imageBase64: smallBase64,
            maxTokens: 80,
            imageDetail: "low"
        )

        guard let raw = result else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Бос немесе тым қысқа (<5 символ) — өткізіп жібер
        guard text.count > 4 else { return }

        // GPT "ештеңе жоқ" деп мета-жауап берсе — өткізіп жібер
        let lower = text.lowercased()
        guard !noisePatterns.contains(where: { lower.contains($0) }) else { return }

        guard !Task.isCancelled else { return }
        onAlert?(text)
    }
}
