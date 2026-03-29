import Foundation
import FirebaseAuth

/// AssistantCoordinator сияқты MainActor емес жерлерден
/// қазіргі Firebase UID-ді оқу үшін жеңіл жол.
final class AuthServiceHolder {
    static let shared = AuthServiceHolder()
    private init() {}

    var currentUID: String? { Auth.auth().currentUser?.uid }
}
