import Foundation

enum DetectedLanguage: String {
    case kazakh = "kk"
    case russian = "ru"
    case english = "en"

    var ttsLocaleIdentifier: String {
        switch self {
        case .kazakh:  return "kk-KZ"
        case .russian: return "ru-RU"
        case .english: return "en-US"
        }
    }
}

enum LanguageResolver {

    private static let kazakhSpecificChars: Set<Character> = [
        "ә", "і", "ң", "ғ", "ү", "ұ", "қ", "ө", "һ",
        "Ә", "І", "Ң", "Ғ", "Ү", "Ұ", "Қ", "Ө", "Һ"
    ]

    private static let cyrillicRange = UnicodeScalar("А")...UnicodeScalar("я")

    static func resolve(text: String, whisperLanguage: String? = nil) -> DetectedLanguage {
        // 1. If Whisper returned a language code
        if let lang = whisperLanguage?.lowercased() {
            if lang.hasPrefix("kk") || lang.hasPrefix("kaz") { return .kazakh }
            if lang.hasPrefix("ru") || lang.hasPrefix("rus") { return .russian }
            if lang.hasPrefix("en") || lang.hasPrefix("eng") { return .english }
        }

        // 2. Check for Kazakh-specific characters
        if text.contains(where: { kazakhSpecificChars.contains($0) }) {
            return .kazakh
        }

        // 3. Check for Cyrillic → Russian
        if text.unicodeScalars.contains(where: { cyrillicRange.contains($0) }) {
            return .russian
        }

        // 4. Fallback → English
        return .english
    }
}
