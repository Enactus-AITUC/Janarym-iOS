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
        switch self {
        case .permissionDenied(let detail):
            return "Рұқсат берілмеді: \(detail)"
        case .cameraUnavailable:
            return "Камера қолжетімсіз"
        case .microphoneUnavailable:
            return "Микрофон қолжетімсіз"
        case .recordingFailed(let detail):
            return "Жазу қатесі: \(detail)"
        case .voiceInputFailed(let detail):
            return "Дауыс енгізу қатесі: \(detail)"
        case .assistantResponseFailed(let detail):
            return "Gemini жауабының қатесі: \(detail)"
        case .ttsFailed(let detail):
            return "TTS қатесі: \(detail)"
        case .missingAPIKey:
            return "API кілті табылмады"
        case .networkError(let detail):
            return "Желі қатесі: \(detail)"
        }
    }
}
