import SwiftUI
import MapKit
import FirebaseFirestore

// MARK: - ViewModel

@MainActor
final class MentorDashboardVM: ObservableObject {

    @Published var members: [AppUser] = []
    @Published var presences: [String: MemberPresence] = [:]   // uid → presence
    @Published var sosUserIds: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var sosListener: ListenerRegistration?
    private var presenceListeners: [String: ListenerRegistration] = [:]
    private let kk: Bool

    init(kk: Bool) {
        self.kk = kk
    }

    func load(mentorId: String, role: UserRole) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                // Admin: барлық member, Mentor: өздікі ғана
                let allUsers = role == .admin
                    ? try await FirestoreService.shared.fetchAllUsers()
                    : try await FirestoreService.shared.fetchMembers(mentorId: mentorId)
                members = allUsers.filter { $0.role == .member }

                // Real-time presence listener — әр member үшін жеке
                self.presenceListeners.values.forEach { $0.remove() }
                self.presenceListeners = [:]
                for user in self.members {
                    let listener = FirestoreService.shared.listenPresence(userId: user.id) { [weak self] p in
                        guard let self else { return }
                        if let p { self.presences[user.id] = p }
                    }
                    self.presenceListeners[user.id] = listener
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }

        // SOS real-time listener
        sosListener?.remove()
        sosListener = FirestoreService.shared.listenSOS(mentorId: mentorId) { [weak self] ids in
            self?.sosUserIds = Set(ids)
        }
    }

    func clearSOS(userId: String) {
        sosUserIds.remove(userId)
        Task { await FirestoreService.shared.clearSOS(userId: userId) }
    }

    deinit {
        sosListener?.remove()
        presenceListeners.values.forEach { $0.remove() }
    }
}

// MARK: - Dashboard

struct MentorDashboardView: View {

    let user: AppUser
    @StateObject private var vm: MentorDashboardVM
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var onboarding = OnboardingStore.shared

    private var kk: Bool { onboarding.currentLanguage == .kazakh }

    init(user: AppUser) {
        self.user = user
        _vm = StateObject(wrappedValue: MentorDashboardVM(
            kk: OnboardingStore.shared.profile.language == .kazakh
        ))
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                if vm.isLoading {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else if vm.members.isEmpty {
                    emptyState
                } else {
                    memberList
                }
            }
        }
        .onAppear {
            vm.load(mentorId: user.id, role: user.role)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kk ? "Панель" : "Панель")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Text(user.role.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(user.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            // SOS badge
            if !vm.sosUserIds.isEmpty {
                SOSBadge(count: vm.sosUserIds.count)
            }
            // Refresh
            Button {
                vm.load(mentorId: user.id, role: user.role)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .padding(.leading, 6)
            // Logout
            Button {
                authService.signOut()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .padding(.leading, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 16)
    }

    // MARK: - List

    private var memberList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14) {
                ForEach(vm.members) { member in
                    MemberCard(
                        member: member,
                        presence: vm.presences[member.id],
                        sosActive: vm.sosUserIds.contains(member.id),
                        kk: kk,
                        onClearSOS: { vm.clearSOS(userId: member.id) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.2.slash")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.2))
            Text(kk ? "Тіркелген мүшелер жоқ" : "Нет прикреплённых участников")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

// MARK: - SOS Badge (header)

private struct SOSBadge: View {
    let count: Int
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(), value: pulse)
                .onAppear { pulse = true }
            Text("SOS · \(count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.red.opacity(0.25)))
        .overlay(Capsule().strokeBorder(Color.red.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Member Card

private struct MemberCard: View {

    let member: AppUser
    let presence: MemberPresence?
    let sosActive: Bool
    let kk: Bool
    let onClearSOS: () -> Void

    @State private var showDetail = false
    @State private var region: MKCoordinateRegion

    init(member: AppUser, presence: MemberPresence?,
         sosActive: Bool, kk: Bool, onClearSOS: @escaping () -> Void) {
        self.member = member
        self.presence = presence
        self.sosActive = sosActive
        self.kk = kk
        self.onClearSOS = onClearSOS
        let coord = CLLocationCoordinate2D(
            latitude:  presence?.lat ?? 51.18,
            longitude: presence?.lng ?? 71.45
        )
        _region = State(initialValue: MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // SOS alert bar
            if sosActive {
                SOSAlertBar(name: member.name, kk: kk, onClear: onClearSOS)
            }

            HStack(alignment: .top, spacing: 14) {
                // Mini map
                if let p = presence {
                    miniMap(lat: p.lat, lng: p.lng)
                } else {
                    noLocationPlaceholder
                }

                // Info column
                VStack(alignment: .leading, spacing: 8) {
                    Text(member.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let p = presence {
                        infoRow(icon: "clock", text: lastSeenText(p.lastSeen))
                        infoRow(icon: "battery.\(batteryIcon(p.battery))",
                                text: "\(Int(p.battery * 100))%",
                                color: batteryColor(p.battery))
                        infoRow(icon: "mappin.circle", text: coordText(p))
                    } else {
                        Text(kk ? "Деректер жоқ" : "Нет данных")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                Spacer()

                // Last photo
                if let urlStr = presence?.lastPhotoURL,
                   let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        default:
                            photoPlaceholder
                        }
                    }
                } else {
                    photoPlaceholder
                }
            }
            .padding(14)
        }
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(sosActive ? 0.06 : 0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            sosActive ? Color.red.opacity(0.5) : Color.white.opacity(0.08),
                            lineWidth: sosActive ? 1.5 : 1
                        )
                }
        }
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            MemberDetailView(member: member, presence: presence,
                             sosActive: sosActive, kk: kk, onClearSOS: onClearSOS)
        }
    }

    // MARK: Map

    private func miniMap(lat: Double, lng: Double) -> some View {
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let r = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
        return Map(coordinateRegion: .constant(r),
                   annotationItems: [MapPin(coord: coord)]) { pin in
            MapMarker(coordinate: pin.coord, tint: .red)
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(true)
    }

    private var noLocationPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.06))
            .frame(width: 80, height: 80)
            .overlay {
                Image(systemName: "location.slash")
                    .foregroundStyle(.white.opacity(0.25))
            }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.06))
            .frame(width: 56, height: 56)
            .overlay {
                Image(systemName: "camera.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.2))
            }
    }

    // MARK: Helpers

    private func infoRow(icon: String, text: String, color: Color = .white) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color.opacity(0.6))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(color.opacity(0.75))
        }
    }

    private func lastSeenText(_ date: Date) -> String {
        let diff = Int(-date.timeIntervalSinceNow)
        if diff < 60 { return kk ? "Қазір онлайн" : "Онлайн" }
        if diff < 3600 { return kk ? "\(diff/60) мин бұрын" : "\(diff/60) мин назад" }
        if diff < 86400 { return kk ? "\(diff/3600) сағ бұрын" : "\(diff/3600) ч назад" }
        return kk ? "\(diff/86400) күн бұрын" : "\(diff/86400) д назад"
    }

    private func coordText(_ p: MemberPresence) -> String {
        String(format: "%.4f, %.4f", p.lat, p.lng)
    }

    private func batteryIcon(_ level: Double) -> String {
        if level > 0.75 { return "100" }
        if level > 0.5  { return "75" }
        if level > 0.25 { return "50" }
        return "25"
    }

    private func batteryColor(_ level: Double) -> Color {
        if level > 0.5 { return .green }
        if level > 0.2 { return .yellow }
        return .red
    }
}

// MARK: - SOS Alert Bar

private struct SOSAlertBar: View {
    let name: String
    let kk: Bool
    let onClear: () -> Void
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sos")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .scaleEffect(pulse ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(), value: pulse)
                .onAppear { pulse = true }

            Text(kk ? "\(name) жәрдем сұрауда!" : "\(name) просит помощи!")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                onClear()
            } label: {
                Text(kk ? "Жабу" : "Закрыть")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.3))
    }
}

// MARK: - Member Detail (full-screen sheet)

private struct MemberDetailView: View {
    let member: AppUser
    let presence: MemberPresence?
    let sosActive: Bool
    let kk: Bool
    let onClearSOS: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showFullPhoto = false
    @State private var mapRegion: MKCoordinateRegion

    init(member: AppUser, presence: MemberPresence?,
         sosActive: Bool, kk: Bool, onClearSOS: @escaping () -> Void) {
        self.member = member
        self.presence = presence
        self.sosActive = sosActive
        self.kk = kk
        self.onClearSOS = onClearSOS
        let coord = CLLocationCoordinate2D(
            latitude:  presence?.lat ?? 51.18,
            longitude: presence?.lng ?? 71.45
        )
        _mapRegion = State(initialValue: MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
        ))
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                            Text(member.email)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 56)
                    .padding(.bottom, 20)

                    // SOS bar
                    if sosActive {
                        SOSAlertBar(name: member.name, kk: kk, onClear: {
                            onClearSOS()
                            dismiss()
                        })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }

                    // Stats row
                    if let p = presence {
                        HStack(spacing: 12) {
                            statCard(icon: "clock.fill", color: .blue,
                                     value: lastSeenText(p.lastSeen),
                                     label: kk ? "Соңғы онлайн" : "Был онлайн")
                            statCard(icon: "battery.75", color: batteryColor(p.battery),
                                     value: "\(Int(p.battery * 100))%",
                                     label: kk ? "Батарея" : "Батарея")
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }

                    // Large map
                    if let p = presence {
                        Map(coordinateRegion: $mapRegion,
                            annotationItems: [MapPin(coord: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng))]) { pin in
                            MapMarker(coordinate: pin.coord, tint: .red)
                        }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .onAppear {
                            mapRegion.center = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
                        }

                        // Coordinates
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                            Text(String(format: "%.5f, %.5f", p.lat, p.lng))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 200)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "location.slash.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.white.opacity(0.2))
                                    Text(kk ? "Орналасу белгісіз" : "Местоположение неизвестно")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }

                    // Last photo
                    VStack(alignment: .leading, spacing: 12) {
                        Text(kk ? "Соңғы фото" : "Последнее фото")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 20)

                        if let urlStr = presence?.lastPhotoURL, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .onTapGesture { showFullPhoto = true }
                                default:
                                    photoPlaceholder
                                }
                            }
                            .padding(.horizontal, 16)
                        } else {
                            photoPlaceholder.padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFullPhoto) {
            if let urlStr = presence?.lastPhotoURL, let url = URL(string: urlStr) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFit()
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.05))
            .frame(maxWidth: .infinity).frame(height: 160)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "camera.slash.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.2))
                    Text(kk ? "Фото жоқ" : "Нет фото")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
    }

    private func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        .frame(maxWidth: .infinity)
    }

    private func lastSeenText(_ date: Date) -> String {
        let diff = Int(-date.timeIntervalSinceNow)
        if diff < 60 { return kk ? "Қазір" : "Онлайн" }
        if diff < 3600 { return kk ? "\(diff/60) мин" : "\(diff/60) мин" }
        if diff < 86400 { return kk ? "\(diff/3600) сағ" : "\(diff/3600) ч" }
        return kk ? "\(diff/86400) күн" : "\(diff/86400) д"
    }

    private func batteryColor(_ level: Double) -> Color {
        if level > 0.5 { return .green }
        if level > 0.2 { return .yellow }
        return .red
    }
}

// MARK: - Map helper

private struct MapPin: Identifiable {
    let id = UUID()
    let coord: CLLocationCoordinate2D
}
