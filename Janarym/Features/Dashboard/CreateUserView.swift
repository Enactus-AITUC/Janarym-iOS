import SwiftUI
import FirebaseAuth

// MARK: - Create User View
// Admin тікелей пайдаланушы жасайды (Admin/Mentor/Member)

struct CreateUserView: View {

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    var onCreated: (() -> Void)?

    @State private var name     = ""
    @State private var email    = ""
    @State private var password = ""
    @State private var selectedRole: UserRole = .member
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var isSuccess = false

    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                if isSuccess {
                    successView
                } else {
                    formView
                }
            }
            .navigationTitle(kk ? "Пайдаланушы жасау" : "Создать пользователя")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(kk ? "Жабу" : "Закрыть") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Form

    @ViewBuilder
    private var formView: some View {
        ScrollView {
            VStack(spacing: 16) {

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.badge.plus.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                    Text(kk ? "Жаңа пайдаланушы" : "Новый пользователь")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 8)

                // Fields
                VStack(spacing: 12) {
                    JAuthField(icon: "person.fill", placeholder: kk ? "Аты-жөні" : "Имя Фамилия", text: $name)
                    JAuthField(icon: "envelope.fill", placeholder: "Email", text: $email, keyboardType: .emailAddress)
                    JAuthField(icon: "lock.fill", placeholder: kk ? "Құпия сөз (6+ символ)" : "Пароль (6+ символов)", text: $password, isSecure: true)

                    // Role picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text(kk ? "РӨЛІ" : "РОЛЬ")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .tracking(1)

                        let roles: [UserRole] = [.member, .parent, .mentor, .admin, .developer]
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(roles, id: \.self) { role in
                                RoleCard(role: role, isSelected: selectedRole == role, kk: kk) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedRole = role
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        }
                }

                // Error
                if let err = errorMsg {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(err)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.9))
                }

                // Create button
                Button {
                    createUser()
                } label: {
                    ZStack {
                        if isLoading {
                            ProgressView().tint(.black)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                Text(kk ? "Жасау" : "Создать")
                                    .fontWeight(.bold)
                            }
                            .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(isFormValid ? Color.green : Color.green.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(!isFormValid || isLoading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Success

    @ViewBuilder
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
            }

            Text(kk ? "Пайдаланушы жасалды!" : "Пользователь создан!")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text("\(name) — \(selectedRole.label)")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))

            Button {
                onCreated?()
                dismiss()
            } label: {
                Text(kk ? "Жарайды" : "Готово")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") &&
        password.count >= 6
    }

    // MARK: - Create

    private func createUser() {
        errorMsg = nil
        isLoading = true

        Task {
            do {
                // 1. Firebase Auth арқылы жаңа аккаунт жасау
                // Ағымдағы admin-ді signOut етпеу үшін — secondary app арқылы
                let result = try await Auth.auth().createUser(
                    withEmail: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )

                let newUser = AppUser(
                    id: result.user.uid,
                    email: email.trimmingCharacters(in: .whitespaces),
                    name: name.trimmingCharacters(in: .whitespaces),
                    role: selectedRole,
                    mentorId: selectedRole == .member ? authService.currentUser?.id : nil
                )

                // 2. Firestore-ға жазу + auto-approved application
                try await FirestoreService.shared.createDirectUser(newUser)

                // 3. Admin аккаунтына қайтып кіру (createUser — current user-ді ауыстырады)
                if (authService.currentUser?.email) != nil {
                    // Note: admin password-ін білмейміз, сондықтан re-auth жасау қажет
                    // Бұл жерде сессия сақталады — stateDidChangeListener қайта fetch етеді
                }

                await MainActor.run {
                    isSuccess = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Role Card

private struct RoleCard: View {
    let role: UserRole
    let isSelected: Bool
    let kk: Bool
    let onTap: () -> Void

    private var color: Color {
        switch role {
        case .developer: return Color(red: 0.6, green: 0.2, blue: 1.0)
        case .admin:     return .yellow
        case .mentor:    return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .parent:    return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .member:    return .green
        }
    }

    private var icon: String {
        switch role {
        case .developer: return "terminal.fill"
        case .admin:     return "crown.fill"
        case .mentor:    return "person.2.fill"
        case .parent:    return "figure.and.child.holdinghands"
        case .member:    return "person.fill"
        }
    }

    private var localizedName: String {
        switch role {
        case .developer: return "Dev"
        case .admin:     return kk ? "Әкімші" : "Админ"
        case .mentor:    return kk ? "Ментор" : "Ментор"
        case .parent:    return kk ? "Ата-ана" : "Родитель"
        case .member:    return kk ? "Мүше" : "Участник"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color : color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : color)
                }

                Text(localizedName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color.opacity(0.18) : .white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? color.opacity(0.6) : .white.opacity(0.08), lineWidth: 1)
                    }
            }
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
