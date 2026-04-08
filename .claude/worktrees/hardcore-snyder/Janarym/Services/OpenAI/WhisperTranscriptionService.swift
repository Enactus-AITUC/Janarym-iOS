import Foundation

// MARK: - WhisperTranscriptionService (Gemini Flash 2.5 арқылы)
//
// Whisper API-дің орнына Gemini 2.5 Flash қолданады.
// transcribe(fileURL:) сигнатурасы өзгермейді —
// AssistantCoordinator handleRecordingComplete() өзгертусіз жұмыс жасайды.

struct WhisperResult {
    let text: String
    let language: String?
}

enum WhisperTranscriptionService {

    private static let transcribePrompt = """
    Transcribe the speech from this audio file. \
    Return ONLY the transcribed text — no explanations, no labels, no formatting. \
    Detect the language automatically (Kazakh, Russian, or English). \
    If the audio is silent or inaudible, return an empty string.
    """

    static func transcribe(fileURL: URL) async throws -> WhisperResult {
        guard !AppConfig.geminiAPIKey.isEmpty else {
            throw AppError.missingAPIKey
        }

        let audioData = try Data(contentsOf: fileURL)
        let mimeType  = mimeType(for: fileURL)

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "inlineData": [
                                "mimeType": mimeType,
                                "data": audioData.base64EncodedString()
                            ]
                        ],
                        ["text": transcribePrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 1024
            ]
        ]

        let urlString = "\(AppConfig.geminiBaseURL)/v1beta/models/\(AppConfig.geminiChatModel)"
            + ":generateContent?key=\(AppConfig.geminiAPIKey)"

        guard let url = URL(string: urlString) else {
            throw AppError.networkError("Жарамсыз URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError("Жауап алынбады")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw AppError.transcriptionFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw AppError.transcriptionFailed("JSON parse error")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Тілді анықтау — LanguageResolver арқылы
        let detectedLang = LanguageResolver.detect(trimmed)
        let langCode: String? = {
            switch detectedLang {
            case .kazakh:  return "kk"
            case .russian: return "ru"
            case .english: return "en"
            }
        }()

        return WhisperResult(text: trimmed, language: langCode)
    }

    // MARK: - MIME type

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3":  return "audio/mp3"
        case "mp4":  return "audio/mp4"
        case "m4a":  return "audio/mp4"
        case "ogg":  return "audio/ogg"
        case "flac": return "audio/flac"
        case "aac":  return "audio/aac"
        case "opus": return "audio/opus"
        default:     return "audio/wav"
        }
    }
}
