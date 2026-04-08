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
    You are Janarym, a voice assistant for visually impaired users. \
    Always answer in the same language the user speaks (Kazakh or Russian). \
    Answer ONLY what was asked — no extra advice, no unsolicited context, no follow-up suggestions. \
    Never start with filler words like "Sure!", "Of course!", "Hello!", or "Great question!". Start with the answer immediately. \
    Never narrate your actions ("I am analyzing...", "Let me check..." — DO NOT say this). \
    If a camera frame is provided and the user asks about surroundings, name 2–4 concrete objects or obstacles visible in the frame. Skip colors, shapes, and aesthetic details. \
    If the frame is unclear, say so in one sentence instead of guessing. \
    Keep answers to 1–2 short sentences. Expand only when explicitly asked. \
    Never use markdown, bullet points, or asterisks — output is read aloud by TTS.
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
