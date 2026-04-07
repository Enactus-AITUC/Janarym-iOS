import Foundation
import Combine

// MARK: - MedCardViewModel
// @MainActor singleton — mirrors the ObservableObject pattern used throughout the app.

@MainActor
final class MedCardViewModel: ObservableObject {

    static let shared = MedCardViewModel()

    @Published var card: MedCard = MedCard()

    private let repo = MedCardRepository.shared

    private init() {
        loadCard()
    }

    // MARK: - Persistence

    func loadCard() {
        card = repo.load()
    }

    func saveCard() {
        repo.save(card)
    }

    // MARK: - Medications

    func addMedication(_ med: Medication) {
        card.medications.append(med)
        repo.save(card)
    }

    func removeMedication(withID id: UUID) {
        card.medications.removeAll { $0.id == id }
        repo.save(card)
    }

    func removeMedications(at offsets: IndexSet) {
        card.medications.remove(atOffsets: offsets)
        repo.save(card)
    }

    func updateMedication(_ med: Medication) {
        guard let idx = card.medications.firstIndex(where: { $0.id == med.id }) else { return }
        card.medications[idx] = med
        repo.save(card)
    }

    // MARK: - Allergies

    func addAllergy(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !card.allergies.contains(t) else { return }
        card.allergies.append(t)
        repo.save(card)
    }

    func removeAllergy(at offsets: IndexSet) {
        card.allergies.remove(atOffsets: offsets)
        repo.save(card)
    }

    // MARK: - Chronic conditions

    func addCondition(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !card.chronicConditions.contains(t) else { return }
        card.chronicConditions.append(t)
        repo.save(card)
    }

    func removeCondition(at offsets: IndexSet) {
        card.chronicConditions.remove(atOffsets: offsets)
        repo.save(card)
    }
}
