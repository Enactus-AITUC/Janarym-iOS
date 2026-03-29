import Foundation

struct WhisperResult {
    let text: String
    let language: String?
}

enum WhisperTranscriptionService {

    static func transcribe(fileURL: URL) async throws -> WhisperResult {
        guard !AppConfig.openAIAPIKey.isEmpty else {
            throw AppError.missingAPIKey
        }

        let audioData = try Data(contentsOf: fileURL)

        var builder = MultipartFormDataBuilder()
        builder.addFile(
            name: "file",
            fileName: "audio.wav",
            mimeType: "audio/wav",
            data: audioData
        )
        builder.addField(name: "model", value: AppConfig.whisperModel)
        builder.addField(name: "response_format", value: "verbose_json")

        let body = builder.build()
        let request = OpenAIClient.request(
            path: "/v1/audio/transcriptions",
            body: body,
            contentType: builder.contentType
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError("Жауап алынбады")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw AppError.transcriptionFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw AppError.transcriptionFailed("JSON parse error")
        }

        let language = json["language"] as? String
        return WhisperResult(text: text, language: language)
    }
}
