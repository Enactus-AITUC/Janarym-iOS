import Foundation

enum AppError: LocalizedError {
    case permissionDenied(String)
    case cameraUnavailable
    case microphoneUnavailable
    case speechRecognitionUnavailable
    case recordingFailed(String)
    case transcriptionFailed(String)
    case chatFailed(String)
    case ttsFailed(String)
    case missingAPIKey
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let detail):
            return "Рұқсат берілмеді: \(detail)"
        case .cameraUnavailable:
            return "Камера қолжетімсіз"
        case .microphoneUnavailable:
            return "Микрофон қолжетімсіз"
        case .speechRecognitionUnavailable:
            return "Сөйлеуді тану қолжетімсіз"
        case .recordingFailed(let detail):
            return "Жазу қатесі: \(detail)"
        case .transcriptionFailed(let detail):
            return "Транскрипция қатесі: \(detail)"
        case .chatFailed(let detail):
            return "GPT қатесі: \(detail)"
        case .ttsFailed(let detail):
            return "TTS қатесі: \(detail)"
        case .missingAPIKey:
            return "API кілті табылмады"
        case .networkError(let detail):
            return "Желі қатесі: \(detail)"
        }
    }
}
