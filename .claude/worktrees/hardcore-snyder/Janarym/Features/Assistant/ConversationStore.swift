import Foundation

struct ChatMessage {
    let role: String   // "system", "user", "assistant"
    let content: String

    var asDictionary: [String: String] {
        ["role": role, "content": content]
    }
}

final class ConversationStore: ObservableObject {

    @Published private(set) var messages: [ChatMessage] = []

    func addUser(_ text: String) {
        messages.append(ChatMessage(role: "user", content: text))
        trimIfNeeded()
    }

    func addAssistant(_ text: String) {
        messages.append(ChatMessage(role: "assistant", content: text))
        trimIfNeeded()
    }

    func clear() {
        messages.removeAll()
    }

    func messagesForAPI(navigationContext: String? = nil, activeMode: AppMode = .general, maxMessages: Int? = nil) -> [[String: String]] {
        var systemContent = OnboardingStore.shared.systemPrompt
        let modeExtra = OnboardingStore.shared.modePrompt(for: activeMode)
        if !modeExtra.isEmpty {
            systemContent += "\n\n" + modeExtra
        }
        if let navCtx = navigationContext, !navCtx.isEmpty {
            systemContent += "\n\n" + navCtx
        }
        var result: [[String: String]] = [
            ["role": "system", "content": systemContent]
        ]
        // Tier-ге байланысты контекст саны (Free:4, Premium:6, VIP:10)
        let limit = maxMessages ?? AppConfig.maxConversationMessages
        let trimmed = messages.count > limit ? Array(messages.suffix(limit)) : messages
        result.append(contentsOf: trimmed.map(\.asDictionary))
        return result
    }

    private func trimIfNeeded() {
        let max = AppConfig.maxConversationMessages
        if messages.count > max {
            messages = Array(messages.suffix(max))
        }
    }
}
