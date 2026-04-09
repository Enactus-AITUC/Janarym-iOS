import AVFoundation
import SwiftUI

// MARK: - Speech preview helper

private final class SpeechPreview: ObservableObject {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String, language: UserProfile.Language, avRate: Float) {
        synth.stopSpeaking(at: .immediate)
        let langCode = language == .kazakh ? "kk-KZ" : "ru-RU"
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: langCode) ?? AVSpeechSynthesisVoice(language: "ru-RU")
        utt.rate = avRate
        synth.speak(utt)
    }
}

// MARK: - SettingsView

struct SettingsView: View {

    @ObservedObject private var store = OnboardingStore.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = SpeechPreview()

    private var kk: Bool { store.profile.language == .kazakh }

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    focusModeSection
                    speechRateSection
                    responseLengthSection
                    formalitySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea())
            .navigationTitle(kk ? "Баптаулар" : "Настройки")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(kk ? "Жабу" : "Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .colorScheme(.dark)
        }
    }

    // MARK: - Focus mode

    private var focusModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(kk ? "Камера фокусы" : "Фокус камеры")
            ForEach(UserProfile.FocusMode.allCases, id: \.self) { mode in
                focusModeCard(mode)
            }
        }
    }

    private func focusModeCard(_ mode: UserProfile.FocusMode) -> some View {
        let isSelected = store.profile.focusMode == mode
        return Button {
            var p = store.profile
            p.focusMode = mode
            store.updateProfile(p)
            preview.speak(
                mode.announcementText(kk: kk),
                language: store.profile.language,
                avRate: store.profile.speechRate.avPreviewRate
            )
        } label: {
            HStack(spacing: 16) {
                Image(systemName: mode.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : Color.green)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName(kk: kk))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isSelected ? .black : .white)
                    Text(mode.descriptionText(kk: kk))
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .black.opacity(0.65) : .white.opacity(0.5))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName(kk: kk))
        .accessibilityHint(mode.descriptionText(kk: kk))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Speech rate

    private var speechRateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(kk ? "Сөйлеу жылдамдығы" : "Скорость речи")
            HStack(spacing: 10) {
                ForEach(UserProfile.SpeechRate.allCases, id: \.self) { rate in
                    speechRateButton(rate)
                }
            }
        }
    }

    private func speechRateButton(_ rate: UserProfile.SpeechRate) -> some View {
        let isSelected = store.profile.speechRate == rate
        return Button {
            var p = store.profile
            p.speechRate = rate
            store.updateProfile(p)
            // Бірден сол жылдамдықта мысал сөйлем айтады
            let sample = kk
                ? "Бұл Жанарым қолданбасы."
                : "Это приложение Жанарым."
            preview.speak(sample, language: store.profile.language, avRate: rate.avPreviewRate)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: rate.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : Color.green)
                Text(rate.display(store.profile.language))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rate.display(store.profile.language))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Response length

    private var responseLengthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(kk ? "Жауап ұзындығы" : "Длина ответа")
            HStack(spacing: 10) {
                ForEach(UserProfile.ResponseLength.allCases, id: \.self) { len in
                    responseLengthButton(len)
                }
            }
        }
    }

    private func responseLengthButton(_ len: UserProfile.ResponseLength) -> some View {
        let isSelected = store.profile.responseLength == len
        return Button {
            var p = store.profile
            p.responseLength = len
            store.updateProfile(p)
            let msg = kk
                ? "\(len.display(.kazakh)) таңдалды"
                : "\(len.display(.russian)) выбрано"
            preview.speak(msg, language: store.profile.language, avRate: store.profile.speechRate.avPreviewRate)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: len.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : Color.green)
                Text(len.display(store.profile.language))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(len.display(store.profile.language))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Formality

    private var formalitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(kk ? "Жүгіну" : "Обращение")
            HStack(spacing: 10) {
                ForEach(UserProfile.Formality.allCases, id: \.self) { formality in
                    formalityButton(formality)
                }
            }
        }
    }

    private func formalityButton(_ formality: UserProfile.Formality) -> some View {
        let isSelected = store.profile.formality == formality
        let lang = store.profile.language
        return Button {
            var p = store.profile
            p.formality = formality
            store.updateProfile(p)
            let msg = kk
                ? "'\(formality.display(.kazakh))' деп жүгіну таңдалды"
                : "Обращение на '\(formality.display(.russian))' выбрано"
            preview.speak(msg, language: lang, avRate: store.profile.speechRate.avPreviewRate)
        } label: {
            VStack(spacing: 6) {
                Text(formality.display(lang))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white)
                Text(formality.formalityLabel(kk: kk))
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .black.opacity(0.65) : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.green : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(formality.display(lang)) — \(formality.formalityLabel(kk: kk))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(0.9)
            .padding(.leading, 4)
    }
}
