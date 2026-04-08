import Foundation

// MARK: - ChatCompletionService (Gemini Flash 2.5)
//
// OpenAI gpt-4o-mini-дің орнына Gemini 2.5 Flash қолданады.
// complete(messages:imageBase64:maxTokens:imageDetail:) сигнатурасы өзгермейді —
// AssistantCoordinator, SceneWatcher т.б. өзгертусіз жұмыс жасайды.

enum ChatCompletionService {

    // MARK: - Public API (OpenAI-мен бірдей сигнатура)

    static func complete(messages: [[String: String]],
                         imageBase64: String? = nil,
                         maxTokens: Int = 500,
                         imageDetail: String = "auto") async throws -> String {
        guard !AppConfig.geminiAPIKey.isEmpty else {
            throw AppError.missingAPIKey
        }

        // OpenAI messages → Gemini contents
        let (systemInstruction, contents) = buildContents(
            from: messages,
            imageBase64: imageBase64
        )

        var payload: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": maxTokens,
                "temperature": 0.7
            ]
        ]

        if let sys = systemInstruction {
            payload["systemInstruction"] = ["parts": [["text": sys]]]
        }

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
            throw AppError.chatFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw AppError.chatFailed("JSON parse error")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenAI → Gemini формат түрлендіру

    /// OpenAI-стиль messages массивін Gemini contents + systemInstruction-ға түрлендіреді.
    private static func buildContents(
        from messages: [[String: String]],
        imageBase64: String?
    ) -> (systemInstruction: String?, contents: [[String: Any]]) {

        var systemInstruction: String?
        var contents: [[String: Any]] = []

        for (idx, msg) in messages.enumerated() {
            let role    = msg["role"] ?? "user"
            let content = msg["content"] ?? ""

            // System → systemInstruction (Gemini жеке параметр ретінде қабылдайды)
            if role == "system" {
                systemInstruction = content
                continue
            }

            // assistant → model (Gemini терминологиясы)
            let geminiRole = role == "assistant" ? "model" : "user"

            // Соңғы user хабарға image қосу
            let isLastUser = role == "user"
                && idx == messages.lastIndex(where: { $0["role"] == "user" })

            if isLastUser, let b64 = imageBase64 {
                contents.append([
                    "role": geminiRole,
                    "parts": [
                        [
                            "inlineData": [
                                "mimeType": "image/jpeg",
                                "data": b64
                            ]
                        ],
                        ["text": content]
                    ]
                ])
            } else {
                contents.append([
                    "role": geminiRole,
                    "parts": [["text": content]]
                ])
            }
        }

        // Егер contents бос болса (тек system болса) — бос user part қосу
        if contents.isEmpty {
            contents.append(["role": "user", "parts": [["text": ""]]])
        }

        return (systemInstruction, contents)
    }
}
