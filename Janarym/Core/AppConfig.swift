import Foundation

enum AppConfig {

    private static func print(_ items: Any...) {}

    // MARK: - API Keys

    static var openAIProxyURL: String {
        let primary = secret(for: "OPENAI_PROXY_URL", warnIfMissing: false)
        if !primary.isEmpty {
            return primary
        }
        return secret(for: "OPENAI_REALTIME_SESSION_URL")
    }

    static var openAIAPIKey: String {
        secret(for: "OPENAI_API_KEY")
    }

    static var yandexMapKitAPIKey: String {
        secret(for: "YANDEX_MAPKIT_API_KEY")
    }

    // MARK: - OpenAI

    static let openAITranscriptionModel = "gpt-4o-transcribe"
    static let openAIVisionModel = "gpt-4.1-mini"
    static let openAITTSModel = "gpt-4o-mini-tts"
    static let openAIVoice = "cedar"

    static let systemPrompt = """
    You are Janarym, a live voice assistant for a phone camera. \
    Always answer in the same language the user speaks. \
    Prioritize Kazakh and Russian speech recognition and reply naturally in Kazakh or Russian when those languages are used. \
    If the user asks what is ahead, what is in front, what they are looking at, or asks about the current surroundings, use the current camera frame as the primary source of truth. \
    In those vision-grounded replies, do not give abstract advice, guesses, or motivational phrases. \
    Mention only 2 to 5 concrete visible objects or obstacles that are actually in front of the user. \
    Do not describe colors, shapes, style, or unnecessary details. \
    If the frame is unclear, say briefly that the frame is unclear instead of inventing details. \
    Usually answer in two short sentences that are easy to read aloud. \
    Avoid markdown, lists, and long explanations unless the user explicitly asks for more detail.
    """

    static let maxRecordingDuration: TimeInterval = 20
    static let presenceMonitoringEnabled = false

    // MARK: - Subscription

    static let premiumProductID = "kz.janarym.premium.monthly"   // 5000₸/ай
    static let vipProductID     = "kz.janarym.vip.monthly"       // 15000₸/ай
    static let freeRequestsPerDay = 5  // Free: 5 сұрақ/күн

    // MARK: - Theme

    static let backgroundColor = "#020617"

    // MARK: - Private

    private static func secret(for key: String, warnIfMissing: Bool = true) -> String {
        // 1. Try Secrets.plist
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let rawValue = dict[key] as? String {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        // 2. Fallback to environment variable
        if let rawEnv = ProcessInfo.processInfo.environment[key] {
            let env = rawEnv.trimmingCharacters(in: .whitespacesAndNewlines)
            if !env.isEmpty {
                return env
            }
        }
        if warnIfMissing {
            print("⚠️ Missing secret: \(key). Add it to Secrets.plist or environment.")
        }
        return ""
    }
}
