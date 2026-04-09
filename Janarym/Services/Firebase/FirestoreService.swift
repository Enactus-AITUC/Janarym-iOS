import Foundation
import FirebaseFirestore

// MARK: - Member Presence Model
struct MemberPresence: Identifiable {
    var id: String { userId }
    let userId: String
    let lat: Double
    let lng: Double
    let battery: Double   // 0.0 – 1.0
    let lastSeen: Date
    let lastPhotoURL: String?
    let sosActive: Bool
    let sosAt: Date?
}

// MARK: - Application Model
struct Application: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var phone: String
    var purpose: String
    var documentURL: String?
    var status: ApplicationStatus
    var rejectionReason: String?   // Қабылдамаған себеп — пайдаланушыға көрсетіледі
    var createdAt: Date
    var userId: String
}

enum ApplicationStatus: String, Codable {
    case pending  = "pending"
    case approved = "approved"
    case rejected = "rejected"
}

// MARK: - Firestore Service
final class FirestoreService {

    static let shared = FirestoreService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Users Collection

    func createUserProfile(_ user: AppUser) async throws {
        var data: [String: Any] = [
            "uid":       user.id,
            "email":     user.email,
            "name":      user.name,
            "role":      user.role.rawValue,
            "mentorId":  user.mentorId as Any
        ]
        if let approved = user.isDirectApproved { data["isDirectApproved"] = approved }
        try await db.collection("users").document(user.id).setData(data)
    }

    func fetchUser(uid: String) async throws -> AppUser {
        let snapshot = try await db.collection("users").document(uid).getDocument()
        guard let data = snapshot.data() else {
            throw NSError(domain: "FirestoreService", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        return AppUser(
            id: uid,
            email: data["email"] as? String ?? "",
            name:  data["name"]  as? String ?? "",
            role:  UserRole(rawValue: data["role"] as? String ?? "member") ?? .member,
            mentorId: data["mentorId"] as? String,
            isDirectApproved: data["isDirectApproved"] as? Bool
        )
    }

    func deleteUserProfile(uid: String) async throws {
        try await db.collection("users").document(uid).delete()
        // presence де өшіру
        try? await db.collection("presence").document(uid).delete()
    }

    func updateUserRole(uid: String, role: UserRole) async throws {
        try await db.collection("users").document(uid).updateData(["role": role.rawValue])
    }

    func fetchAllUsers() async throws -> [AppUser] {
        let snapshot = try await db.collection("users").getDocuments()
        return snapshot.documents.compactMap { doc in
            let d = doc.data()
            return AppUser(
                id: doc.documentID,
                email: d["email"] as? String ?? "",
                name:  d["name"]  as? String ?? "",
                role:  UserRole(rawValue: d["role"] as? String ?? "member") ?? .member,
                mentorId: d["mentorId"] as? String
            )
        }
    }

    // MARK: - Applications Collection

    func submitApplication(_ app: Application) async throws {
        let data: [String: Any] = [
            "name":        app.name,
            "phone":       app.phone,
            "purpose":     app.purpose,
            "documentURL": app.documentURL as Any,
            "status":      app.status.rawValue,
            "createdAt":   Timestamp(date: app.createdAt),
            "userId":      app.userId
        ]
        try await db.collection("applications").addDocument(data: data)
    }

    func fetchApplications(forUserId userId: String? = nil) async throws -> [Application] {
        var query: Query = db.collection("applications")
            .order(by: "createdAt", descending: true)

        if let uid = userId {
            query = query.whereField("userId", isEqualTo: uid)
        }

        let snapshot = try await query.getDocuments()
        return try snapshot.documents.compactMap { doc in
            try doc.data(as: Application.self)
        }
    }

    func updateApplicationStatus(appId: String, status: ApplicationStatus, reason: String? = nil) async throws {
        var data: [String: Any] = ["status": status.rawValue]
        if let reason, !reason.isEmpty { data["rejectionReason"] = reason }
        try await db.collection("applications").document(appId).updateData(data)
    }

    /// Пайдаланушының өтініші бекітілді ме?
    func isApplicationApproved(userId: String) async -> Bool {
        do {
            let snapshot = try await db.collection("applications")
                .whereField("userId", isEqualTo: userId)
                .whereField("status", isEqualTo: "approved")
                .limit(to: 1)
                .getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            return false
        }
    }

    /// Пайдаланушының өтініші статусы + себебі (rejected болса)
    func applicationStatus(userId: String) async -> (ApplicationStatus?, String?) {
        do {
            let snapshot = try await db.collection("applications")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments()
            guard let doc = snapshot.documents.first,
                  let raw = doc.data()["status"] as? String else { return (nil, nil) }
            let reason = doc.data()["rejectionReason"] as? String
            return (ApplicationStatus(rawValue: raw), reason)
        } catch {
            return (nil, nil)
        }
    }

    // MARK: - Presence & SOS (ата-ана бақылауы)

    /// Member presence-ін жаңарту: локация + батарея + соңғы фото
    func updatePresence(userId: String, lat: Double, lng: Double,
                        battery: Double, photoURL: String?) async {
        var data: [String: Any] = [
            "lat": lat, "lng": lng,
            "battery": battery,
            "lastSeen": Timestamp(date: Date())
        ]
        if let url = photoURL { data["lastPhotoURL"] = url }
        try? await db.collection("presence").document(userId).setData(data, merge: true)
    }

    /// Member-лердің presence деректерін бірден алу
    func fetchPresence(userId: String) async -> MemberPresence? {
        guard let doc = try? await db.collection("presence").document(userId).getDocument(),
              let d = doc.data() else { return nil }
        return MemberPresence(
            userId: userId,
            lat: d["lat"] as? Double ?? 0,
            lng: d["lng"] as? Double ?? 0,
            battery: d["battery"] as? Double ?? 0,
            lastSeen: (d["lastSeen"] as? Timestamp)?.dateValue() ?? Date(),
            lastPhotoURL: d["lastPhotoURL"] as? String,
            sosActive: d["sosActive"] as? Bool ?? false,
            sosAt: (d["sosAt"] as? Timestamp)?.dateValue()
        )
    }

    /// Менторға тіркелген member-лерді алу
    func fetchMembers(mentorId: String) async throws -> [AppUser] {
        let snapshot = try await db.collection("users")
            .whereField("mentorId", isEqualTo: mentorId)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            let d = doc.data()
            return AppUser(
                id: doc.documentID,
                email: d["email"] as? String ?? "",
                name:  d["name"]  as? String ?? "",
                role:  UserRole(rawValue: d["role"] as? String ?? "member") ?? .member,
                mentorId: d["mentorId"] as? String
            )
        }
    }

    /// SOS іске қосу — ата-анаға хабар
    func triggerSOS(userId: String, lat: Double, lng: Double) async {
        let data: [String: Any] = [
            "sosActive": true,
            "sosAt": Timestamp(date: Date()),
            "lat": lat, "lng": lng,
            "lastSeen": Timestamp(date: Date())
        ]
        try? await db.collection("presence").document(userId).setData(data, merge: true)
    }

    /// SOS өшіру
    func clearSOS(userId: String) async {
        try? await db.collection("presence").document(userId).updateData(["sosActive": false])
    }

    /// Real-time presence listener — presence жаңарғанда UI автоматты жаңарады
    func listenPresence(userId: String, onChange: @escaping (MemberPresence?) -> Void) -> ListenerRegistration {
        db.collection("presence").document(userId).addSnapshotListener { snap, _ in
            guard let d = snap?.data() else { onChange(nil); return }
            onChange(MemberPresence(
                userId: userId,
                lat: d["lat"] as? Double ?? 0,
                lng: d["lng"] as? Double ?? 0,
                battery: d["battery"] as? Double ?? 0,
                lastSeen: (d["lastSeen"] as? Timestamp)?.dateValue() ?? Date(),
                lastPhotoURL: d["lastPhotoURL"] as? String,
                sosActive: d["sosActive"] as? Bool ?? false,
                sosAt: (d["sosAt"] as? Timestamp)?.dateValue()
            ))
        }
    }

    /// Real-time SOS listener — ата-ана жағы
    func listenSOS(mentorId: String, onChange: @escaping ([String]) -> Void) -> ListenerRegistration {
        db.collection("presence")
            .whereField("sosActive", isEqualTo: true)
            .addSnapshotListener { snapshot, _ in
                let ids = snapshot?.documents.map(\.documentID) ?? []
                onChange(ids)
            }
    }

    // MARK: - Admin: тікелей пайдаланушы жасау (Firestore-ға ғана)
    func createDirectUser(_ user: AppUser) async throws {
        // isDirectApproved = true — pending экран шықпасын
        var approved = user
        approved = AppUser(id: user.id, email: user.email, name: user.name,
                           role: user.role, mentorId: user.mentorId, isDirectApproved: true)
        try await createUserProfile(approved)
    }

    // MARK: - BLE Linking

    /// Publish short discovery token so child can look up parent UID via BLE local name
    func publishDiscoveryToken(uid: String) async {
        let shortCode = String(uid.prefix(8)).uppercased()
        try? await db.collection("discoveryTokens").document(shortCode).setData([
            "uid":       uid,
            "createdAt": Timestamp(date: Date())
        ])
    }

    /// Child sends link request after tapping discovered parent device
    func sendBLELinkRequest(childUID: String, parentShortCode: String) async {
        do {
            let snap = try await db.collection("discoveryTokens")
                .document(parentShortCode)
                .getDocument()
            guard let data = snap.data(),
                  let parentUID = data["uid"] as? String else { return }
            let requestID = "\(childUID)_\(parentUID)"
            try await db.collection("linkRequests").document(requestID).setData([
                "childUid":  childUID,
                "parentUid": parentUID,
                "status":    "pending",
                "createdAt": Timestamp(date: Date())
            ])
        } catch {}
    }

    /// Parent accepts link request — updates both user docs
    func acceptLinkRequest(requestID: String, parentUID: String, childUID: String) async {
        do {
            try await db.collection("linkRequests")
                .document(requestID)
                .updateData(["status": "accepted"])
            try await db.collection("users").document(parentUID)
                .updateData(["children": FieldValue.arrayUnion([childUID])])
            try await db.collection("users").document(childUID)
                .setData(["parentUid": parentUID, "isLinked": true], merge: true)
        } catch {}
    }

    /// Listen for incoming link requests targeting parentUID
    func listenLinkRequests(parentUID: String,
                            onChange: @escaping ([String: Any]) -> Void) -> ListenerRegistration {
        db.collection("linkRequests")
            .whereField("parentUid", isEqualTo: parentUID)
            .whereField("status",    isEqualTo: "pending")
            .addSnapshotListener { snap, _ in
                snap?.documents.forEach { onChange($0.data()) }
            }
    }

    // MARK: - Child location & battery (parent dashboard)

    func updateChildLocation(uid: String, lat: Double, lng: Double) async {
        try? await db.collection("users").document(uid)
            .setData(["location": ["lat": lat, "lng": lng,
                                   "updatedAt": Timestamp(date: Date())]], merge: true)
    }

    func updateBatteryLog(uid: String, pct: Int) async {
        let entry: [String: Any] = ["pct": pct, "timestamp": Timestamp(date: Date())]
        // arrayUnion adds entry; pruning to last 5 handled client-side after read
        try? await db.collection("users").document(uid)
            .setData(["batteryLog": FieldValue.arrayUnion([entry])], merge: true)
    }

    func saveMedCard(childUID: String, data: [String: Any]) async {
        try? await db.collection("users").document(childUID)
            .setData(["medCard": data], merge: true)
    }

    func fetchMedCard(childUID: String) async -> [String: Any]? {
        guard let doc = try? await db.collection("users").document(childUID).getDocument(),
              let d = doc.data() else { return nil }
        return d["medCard"] as? [String: Any]
    }

    func saveSymptom(childUID: String, text: String, audioURL: String?, recordedBy: String) async {
        let entry: [String: Any] = [
            "text":       text,
            "audioUrl":   audioURL as Any,
            "timestamp":  Timestamp(date: Date()),
            "recordedBy": recordedBy
        ]
        try? await db.collection("users").document(childUID)
            .setData(["symptoms": FieldValue.arrayUnion([entry])], merge: true)
    }

    func saveAIPhotoRecord(childUID: String, timestamp: String, url: String, description: String) async {
        let data: [String: Any] = [
            "url":         url,
            "description": description,
            "createdAt":   Timestamp(date: Date())
        ]
        try? await db.collection("ai_photos").document(childUID)
            .setData([timestamp: data], merge: true)
    }
}
