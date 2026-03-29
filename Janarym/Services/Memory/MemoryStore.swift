import Foundation

// MARK: - MemoryStore
// Пайдаланушы "есте сақта" деген нәрселерді UserDefaults-та сақтайды
// GPT system prompt-қа контекст ретінде қосылады

final class MemoryStore {

    static let shared = MemoryStore()
    private let key = "janarym.memories.v1"
    private let maxCount = 20

    private init() {}

    // MARK: - CRUD

    var all: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    func add(_ memory: String) {
        let trimmed = memory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = all
        // Дубликат болдырмау
        if current.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) { return }
        current.append(trimmed)
        if current.count > maxCount { current.removeFirst() }
        all = current
    }

    func remove(containing keyword: String) {
        all = all.filter { !$0.localizedCaseInsensitiveContains(keyword) }
    }

    func clear() {
        all = []
    }

    // MARK: - GPT prompt context

    func promptContext(kazakh: Bool) -> String {
        let memories = all
        guard !memories.isEmpty else { return "" }
        let header = kazakh
            ? "Пайдаланушы есте сақтауды өтінген деректер (контекст ретінде пайдалан):"
            : "Данные, которые пользователь попросил запомнить (используй как контекст):"
        let lines = memories.enumerated().map { "\($0.offset + 1). \($0.element)" }
        return header + "\n" + lines.joined(separator: "\n")
    }

    // MARK: - Detect memory intent in transcription

    /// Пайдаланушының сөзінде "есте сақта", "запомни" деген бар ма?
    func extractMemoryIntent(from text: String) -> String? {
        let lower = text.lowercased()
        let triggers = ["есте сақта", "жаттап ал", "біліп қой",
                        "запомни", "запомни это", "сохрани"]
        guard triggers.contains(where: { lower.contains($0) }) else { return nil }

        // "есте сақта: менің туған күнім 5 мамыр" → "менің туған күнім 5 мамыр"
        let separators = ["есте сақта:", "есте сақта ", "жаттап ал:", "жаттап ал ",
                          "запомни:", "запомни ", "сохрани:"]
        for sep in separators {
            if let range = lower.range(of: sep) {
                let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !after.isEmpty { return after }
            }
        }
        // Separator табылмаса — бүкіл мәтінді сақта
        return text
    }

    /// "ұмыт", "забудь" деген бар ма?
    func extractForgetIntent(from text: String) -> String? {
        let lower = text.lowercased()
        let triggers = ["ұмыт", "өшір", "забудь", "удали из памяти"]
        guard triggers.contains(where: { lower.contains($0) }) else { return nil }
        // Keyword-дан кейінгі нәрсені қайтар
        for trigger in triggers {
            if let range = lower.range(of: trigger) {
                let after = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                if !after.isEmpty { return after }
            }
        }
        return nil
    }
}
