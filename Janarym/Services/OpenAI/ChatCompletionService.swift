import Foundation

enum ChatCompletionService {

    /// - Parameters:
    ///   - messages: system + conversation history (role/content string pairs)
    ///   - imageBase64: камера кадры (JPEG base64)
    ///   - maxTokens: жауап ұзындығы (SceneWatcher: 80, қалған: 500)
    ///   - imageDetail: "low" = 85 tokens, "auto" = GPT өзі анықтайды
    static func complete(messages: [[String: String]],
                         imageBase64: String? = nil,
                         maxTokens: Int = 500,
                         imageDetail: String = "auto") async throws -> String {
        guard !AppConfig.openAIAPIKey.isEmpty else {
            throw AppError.missingAPIKey
        }

        var apiMessages: [[String: Any]] = messages.map { msg in
            ["role": msg["role"] ?? "user", "content": msg["content"] ?? ""]
        }

        // Соңғы user хабарға image қосу (Vision формат)
        if let base64 = imageBase64,
           let lastUserIdx = apiMessages.indices.last(where: {
               (apiMessages[$0]["role"] as? String) == "user"
           }) {
            let text = (apiMessages[lastUserIdx]["content"] as? String) ?? ""
            apiMessages[lastUserIdx]["content"] = [
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(base64)",
                        "detail": imageDetail
                    ]
                ],
                ["type": "text", "text": text]
            ]
        }

        let payload: [String: Any] = [
            "model": AppConfig.chatModel,
            "messages": apiMessages,
            "max_tokens": maxTokens,
            "temperature": 0.7
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = OpenAIClient.request(path: "/v1/chat/completions", body: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError("Жауап алынбады")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw AppError.chatFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AppError.chatFailed("JSON parse error")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
