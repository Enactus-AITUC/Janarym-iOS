import Foundation

enum AppConfig {

    // MARK: - API Keys

    static var openAIAPIKey: String {
        secret(for: "OPENAI_API_KEY")
    }

    static var geminiAPIKey: String {
        secret(for: "GEMINI_API_KEY")
    }

    static var yandexMapKitAPIKey: String {
        secret(for: "YANDEX_MAPKIT_API_KEY")
    }

    // MARK: - Gemini

    static let geminiBaseURL = "https://generativelanguage.googleapis.com"
    static let geminiChatModel = "gemini-2.5-flash"
    static let geminiLiveModel = "gemini-2.5-flash-native-audio-preview"

    // MARK: - OpenAI (fallback — TTS үшін сақталады)

    static let openAIBaseURL = "https://api.openai.com"
    static let whisperModel  = "whisper-1"       // artık қолданылмайды
    static let chatModel     = "gpt-4o-mini"     // artık қолданылмайды

    static let systemPrompt = """
    Сен — Janarym, дауыстық AI-ассистентсің. \
    Қысқа, нақты және пайдалы жауап бер. \
    Пайдаланушы қай тілде сөйлесе, сол тілде жауап бер: \
    қазақша, орысша немесе ағылшынша. \
    Жауабыңды дауыстап оқуға ыңғайлы жаса: \
    markdown, тізімдер немесе тым ұзақ мәтін қолданба, \
    егер пайдаланушы өзі толық жауап сұрамаса.
    """

    static let maxConversationMessages = 6  // 10→6: token үнемдеу
    static let maxRecordingDuration: TimeInterval = 20
    static let silenceThreshold: Float = -40.0
    static let silenceDuration: TimeInterval = 1.2

    // MARK: - Subscription

    static let premiumProductID = "kz.janarym.premium.monthly"   // 5000₸/ай
    static let vipProductID     = "kz.janarym.vip.monthly"       // 15000₸/ай
    static let freeRequestsPerDay = 5  // Free: 5 сұрақ/күн

    // MARK: - Theme

    static let backgroundColor = "#020617"

    // MARK: - Private

    private static func secret(for key: String) -> String {
        // 1. Try Secrets.plist
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let value = dict[key] as? String, !value.isEmpty {
            return value
        }
        // 2. Fallback to environment variable
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        print("⚠️ Missing secret: \(key). Add it to Secrets.plist or environment.")
        return ""
    }
}
