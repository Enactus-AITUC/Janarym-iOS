import Foundation
import FirebaseAuth

// MARK: - User Role
enum UserRole: String, Codable, CaseIterable {
    case developer = "developer" // Барлық рұқсат + техникалық деректер
    case admin     = "admin"
    case mentor    = "mentor"
    case parent    = "parent"    // Ата-ана — баласын бақылайды
    case member    = "member"
}

// MARK: - App User Model
struct AppUser: Codable, Identifiable {
    let id: String          // Firebase UID
    let email: String
    var name: String
    var role: UserRole
    var mentorId: String?   // тек member үшін
    var isDirectApproved: Bool? // Admin тікелей жасаса true — application керек емес
}

// MARK: - Auth Service
@MainActor
final class AuthService: ObservableObject {

    @Published var currentUser: AppUser?
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var isRestoringSession: Bool = true
    @Published var errorMessage: String?
    @Published var applicationStatus: ApplicationStatus?  // nil = жоқ, pending/approved/rejected
    @Published var rejectionReason: String?               // Қабылдамаған себеп

    private let auth = Auth.auth()
    private var stateListener: AuthStateDidChangeListenerHandle?

    init() {
        stateListener = auth.addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                if let firebaseUser {
                    self?.isRestoringSession = true
                    await self?.fetchUserProfile(uid: firebaseUser.uid)
                } else {
                    self?.currentUser = nil
                    self?.isAuthenticated = false
                    self?.isRestoringSession = false
                }
            }
        }
    }

    deinit {
        if let handle = stateListener {
            auth.removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Sign Up
    func signUp(email: String, password: String, name: String, role: UserRole = .member) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            let user = AppUser(
                id: result.user.uid,
                email: email,
                name: name,
                role: role,
                mentorId: nil
            )
            try await FirestoreService.shared.createUserProfile(user)
            self.currentUser = user
            self.isAuthenticated = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign In
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            await fetchUserProfile(uid: result.user.uid)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign Out
    func signOut() {
        do {
            try auth.signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Fetch Profile
    private func fetchUserProfile(uid: String) async {
        do {
            let user = try await FirestoreService.shared.fetchUser(uid: uid)
            self.currentUser = user

            // Admin/Mentor немесе admin тікелей жасаған — тексеру қажет емес
            if user.role == .developer || user.role == .admin || user.role == .mentor || user.isDirectApproved == true {
                self.applicationStatus = .approved
                self.isAuthenticated = true
            } else {
                // Member/Parent — өтініш мақұлданды ма тексеру
                let (status, reason) = await FirestoreService.shared.applicationStatus(userId: uid)
                self.applicationStatus = status
                self.rejectionReason = reason
                self.isAuthenticated = true
            }
        } catch {
            self.errorMessage = error.localizedDescription
            if let firebaseUser = auth.currentUser {
                self.currentUser = AppUser(
                    id: firebaseUser.uid,
                    email: firebaseUser.email ?? "",
                    name: firebaseUser.displayName ?? "",
                    role: .member,
                    mentorId: nil
                )
                let (status, reason) = await FirestoreService.shared.applicationStatus(userId: firebaseUser.uid)
                self.applicationStatus = status
                self.rejectionReason = reason
                self.isAuthenticated = true
            } else {
                self.currentUser = nil
                self.isAuthenticated = false
            }
        }
        self.isRestoringSession = false
    }

    /// Өтініш мақұлданды ма? Admin/Mentor автоматты approved
    var isApproved: Bool {
        guard let user = currentUser else { return false }
        if user.role == .developer || user.role == .admin || user.role == .mentor { return true }
        if user.role == .parent { return applicationStatus == .approved }
        return applicationStatus == .approved
    }
}
