import SwiftUI

// MARK: - EmergencyOverlayView
// Full-screen red overlay — shown on long-press of the emergency banner.
// Designed to be readable at a glance by a first responder.

struct EmergencyOverlayView: View {

    let card: MedCard
    let onDismiss: () -> Void

    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    @State private var pulse = false

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────────
            Color(red: 0.68, green: 0.05, blue: 0.05)
                .ignoresSafeArea()

            // Subtle radial pulse — draws the eye
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 500, height: 500)
                .scaleEffect(pulse ? 1.12 : 0.92)
                .animation(
                    .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }
                .allowsHitTesting(false)

            VStack(spacing: 0) {

                // ── Scrollable content (header + data rows) ──────────
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {

                        // Header
                        VStack(spacing: 6) {
                            Image(systemName: "cross.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                                .accessibilityHidden(true)

                            Text(kk ? "ЖЕДЕЛ МЕДИЦИНАЛЫҚ АҚПАРАТ" : "ЭКСТРЕННЫЕ МЕДДАННЫЕ")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .kerning(0.6)
                        }
                        .padding(.top, 52)
                        .padding(.bottom, 6)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(kk ? "Жедел медициналық ақпарат" : "Экстренные медицинские данные")

                        if !card.fullName.isEmpty {
                            ERow(icon: "person.fill",
                                 label: kk ? "Аты-жөні"   : "ФИО",
                                 value: card.fullName,
                                 large: true)
                        }

                        if let bt = card.bloodType {
                            ERow(icon: "drop.fill",
                                 label: kk ? "Қан тобы"   : "Группа крови",
                                 value: bt.display,
                                 large: true,
                                 valueColor: .yellow)
                        }

                        if !card.allergies.isEmpty {
                            ERow(icon: "exclamationmark.triangle.fill",
                                 label: kk ? "Аллергия"   : "Аллергия",
                                 value: card.allergies.joined(separator: "  •  "),
                                 valueColor: .yellow)
                        }

                        if !card.chronicConditions.isEmpty {
                            ERow(icon: "heart.text.square.fill",
                                 label: kk ? "Созылмалы аурулар" : "Хронические заболевания",
                                 value: card.chronicConditions.joined(separator: "  •  "))
                        }

                        if !card.emergencyContact.isEmpty || !card.emergencyPhone.isEmpty {
                            ERow(icon: "phone.fill",
                                 label: kk ? "Байланыс / Телефон" : "Контакт / Телефон",
                                 value: [card.emergencyContact, card.emergencyPhone]
                                            .filter { !$0.isEmpty }
                                            .joined(separator: "   "),
                                 large: true,
                                 valueColor: Color(red: 0.55, green: 1.0, blue: 0.55))
                        }

                        if !card.emergencyNotes.isEmpty {
                            ERow(icon: "note.text",
                                 label: kk ? "Ескертпе" : "Примечание",
                                 value: card.emergencyNotes)
                        }

                        if !card.doctorName.isEmpty || !card.doctorPhone.isEmpty {
                            ERow(icon: "stethoscope",
                                 label: kk ? "Дәрігер" : "Врач",
                                 value: [card.doctorName, card.doctorPhone]
                                            .filter { !$0.isEmpty }
                                            .joined(separator: "  •  "))
                        }

                        if !card.medications.isEmpty {
                            EMedsBlock(meds: card.medications, kk: kk)
                        }

                        Spacer(minLength: 16)
                    }
                    .padding(.horizontal, 20)
                }

                // ── Dismiss — pinned to bottom ────────────────────────
                Button(action: onDismiss) {
                    Text(kk ? "Жабу" : "Закрыть")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(red: 0.68, green: 0.05, blue: 0.05))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 24)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .accessibilityLabel(kk ? "Жабу" : "Закрыть")
                .accessibilityHint(kk ? "Жедел ақпарат экранын жабады" : "Закрывает экстренный экран")
            }
        }
        .preferredColorScheme(.dark)
        // Tap anywhere (except dismiss button) also closes
        .onTapGesture { onDismiss() }
    }
}

// MARK: - ERow

private struct ERow: View {
    let icon: String
    let label: String
    let value: String
    var large: Bool = false
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.60))
                    .textCase(.uppercase)
                    .kerning(0.8)
            }
            Text(value)
                .font(.system(size: large ? 22 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - EMedsBlock

private struct EMedsBlock: View {
    let meds: [Medication]
    let kk: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "pills.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .accessibilityHidden(true)
                Text(kk ? "ДӘРІЛЕР" : "ПРЕПАРАТЫ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.60))
                    .kerning(0.8)
            }
            ForEach(meds) { med in
                HStack(spacing: 6) {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(med.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    if !med.dosage.isEmpty {
                        Text(med.dosage)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.70))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(med.name) \(med.dosage)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
