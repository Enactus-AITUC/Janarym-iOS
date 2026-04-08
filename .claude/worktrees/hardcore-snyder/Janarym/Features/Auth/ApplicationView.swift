import SwiftUI

// MARK: - Application View (Өтініш беру)

struct ApplicationView: View {

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var name       = ""
    @State private var phone      = ""
    @State private var email      = ""
    @State private var password   = ""
    @State private var purpose    = ""
    @State private var isParent   = false   // false = Мүше, true = Ата-ана
    @State private var isLoading  = false
    @State private var errorMsg: String?
    @State private var isSuccess  = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                if isSuccess {
                    SuccessView(onDone: { dismiss() })
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            VStack(spacing: 8) {
                                Image(systemName: "person.badge.plus.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color.green)
                                Text("Өтініш беру")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("Толтырыңыз — ментор тексеріп аккаунт береді")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 8)

                            // Form card
                            VStack(spacing: 14) {

                                    // Role selector
                                HStack(spacing: 0) {
                                    RoleToggleBtn(
                                        title: "👤 Мүше",
                                        subtitle: "Мен нашар көремін",
                                        selected: !isParent
                                    ) { isParent = false }

                                    RoleToggleBtn(
                                        title: "👨‍👩‍👧 Ата-ана",
                                        subtitle: "Баламды бақылаймын",
                                        selected: isParent
                                    ) { isParent = true }
                                }
                                .background {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.05))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                                        }
                                }

                                SectionLabel("Жеке деректер")

                                JAuthField(icon: "person.fill",
                                           placeholder: "Аты-жөні",
                                           text: $name)

                                JAuthField(icon: "phone.fill",
                                           placeholder: "Телефон нөмірі",
                                           text: $phone,
                                           keyboardType: .phonePad)

                                SectionLabel("Кіру деректері")

                                JAuthField(icon: "envelope.fill",
                                           placeholder: "Email",
                                           text: $email,
                                           keyboardType: .emailAddress)

                                JAuthField(icon: "lock.fill",
                                           placeholder: "Құпия сөз (6+ символ)",
                                           text: $password,
                                           isSecure: true)

                                SectionLabel(isParent ? "Баланыз туралы" : "Неліктен Жанарым керек?")

                                // Purpose textarea
                                ZStack(alignment: .topLeading) {
                                    if purpose.isEmpty {
                                        Text(isParent
                                             ? "Мысалы: Менің балам 8 жаста, нашар көреді, оның қауіпсіздігін бақылағым келеді..."
                                             : "Мысалы: Мен мүлде көрмеймін, Жанарым маған күнделікті өмірде көмектеседі...")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white.opacity(0.3))
                                            .padding(.horizontal, 16)
                                            .padding(.top, 14)
                                    }
                                    TextEditor(text: $purpose)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white)
                                        .scrollContentBackground(.hidden)
                                        .frame(minHeight: 100)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }
                                .background {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.07))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
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

                                // Submit button
                                Button {
                                    submit()
                                } label: {
                                    ZStack {
                                        if isLoading {
                                            ProgressView().tint(.black)
                                        } else {
                                            HStack(spacing: 8) {
                                                Image(systemName: "paperplane.fill")
                                                Text("Өтінішті жіберу")
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
                            .padding(20)
                            .background {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.ultraThinMaterial)
                                    .environment(\.colorScheme, .dark)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 24)
                                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Жабу") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !phone.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") &&
        password.count >= 6 &&
        !purpose.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Submit

    private func submit() {
        errorMsg = nil
        isLoading = true

        Task {
            // 1. Firebase Auth арқылы аккаунт жаса
            await authService.signUp(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                name: name.trimmingCharacters(in: .whitespaces),
                role: isParent ? .parent : .member
            )

            // 2. Firestore-қа өтініш сақта
            if authService.errorMessage == nil,
               let uid = authService.currentUser?.id {
                let app = Application(
                    name: name,
                    phone: phone,
                    purpose: purpose,
                    documentURL: nil,
                    status: .pending,
                    createdAt: Date(),
                    userId: uid
                )
                do {
                    try await FirestoreService.shared.submitApplication(app)
                    await MainActor.run { isSuccess = true }
                } catch {
                    await MainActor.run { errorMsg = error.localizedDescription }
                }
            } else if let err = authService.errorMessage {
                await MainActor.run { errorMsg = err }
            }

            await MainActor.run { isLoading = false }
        }
    }
}

// MARK: - Role Toggle Button

private struct RoleToggleBtn: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: selected ? .bold : .regular))
                    .foregroundStyle(selected ? .white : .white.opacity(0.45))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? .white.opacity(0.7) : .white.opacity(0.25))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.green.opacity(0.5), lineWidth: 1.5)
                        }
                        .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Label

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(1)
            Spacer()
        }
    }
}

// MARK: - Success View

private struct SuccessView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.green)
            }

            VStack(spacing: 12) {
                Text("Өтінішіңіз жіберілді!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text("Ментор немесе әкімші өтінішіңізді тексеріп,\nжуырда хабарласады.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Button {
                onDone()
            } label: {
                Text("Жарайды")
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
}
