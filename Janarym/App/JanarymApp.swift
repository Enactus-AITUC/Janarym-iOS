import SwiftUI
import FirebaseCore

// MARK: - Orientation Manager
// VR режимінде landscape, қалған уақытта portrait
final class OrientationManager {
    static let shared = OrientationManager()
    var isVRMode = false
    private init() {}
}

// MARK: - AppDelegate (Firebase үшін қажет)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }

    // Portrait + Landscape екеуін де қолдайды
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .allButUpsideDown
    }
}

// MARK: - App Entry Point
@main
struct JanarymApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService()

    init() {
        // Audio session-ды background-та конфигурациялаймыз
        DispatchQueue.global(qos: .userInitiated).async {
            AudioSessionManager.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
        }
    }
}
