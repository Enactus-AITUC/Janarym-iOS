import Foundation

enum AppError: LocalizedError {
    case permissionDenied(String)
    case cameraUnavailable
    case microphoneUnavailable
    case recordingFailed(String)
    case voiceInputFailed(String)
    case assistantResponseFailed(String)
    case ttsFailed(String)
    case missingAPIKey
    case networkError(String)

    var errorDescription: String? {
        let language = OnboardingStore.shared.currentLanguage
        switch self {
        case .permissionDenied(let detail):
            return AppText.pick("Рұқсат берілмеді: \(detail)", "Доступ не предоставлен: \(detail)", language: language)
        case .cameraUnavailable:
            return AppText.pick("Камера қолжетімсіз", "Камера недоступна", language: language)
        case .microphoneUnavailable:
            return AppText.pick("Микрофон қолжетімсіз", "Микрофон недоступен", language: language)
        case .recordingFailed(let detail):
            return AppText.pick("Жазу қатесі: \(detail)", "Ошибка записи: \(detail)", language: language)
        case .voiceInputFailed(let detail):
            return AppText.pick("Дауыс енгізу қатесі: \(detail)", "Ошибка голосового ввода: \(detail)", language: language)
        case .assistantResponseFailed(let detail):
            return AppText.pick("Ассистент жауабының қатесі: \(detail)", "Ошибка ответа ассистента: \(detail)", language: language)
        case .ttsFailed(let detail):
            return AppText.pick("TTS қатесі: \(detail)", "Ошибка TTS: \(detail)", language: language)
        case .missingAPIKey:
            return AppText.pick("OPENAI_API_KEY немесе OPENAI_PROXY_URL Secrets.plist-те табылмады", "Не найден OPENAI_API_KEY или OPENAI_PROXY_URL в Secrets.plist", language: language)
        case .networkError(let detail):
            return AppText.pick("Желі қатесі: \(detail)", "Сетевая ошибка: \(detail)", language: language)
        }
    }
}
