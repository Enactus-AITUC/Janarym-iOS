import CoreBluetooth
import Combine
import Foundation

// MARK: - BLE constants

private let kServiceUUID       = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
private let kCharUUID          = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
private let kLocalNamePrefix   = "JNR-"

// MARK: - Distance

enum BLEDeviceDistance: String {
    case veryClose = "Өте жақын"   // RSSI > -60
    case close     = "Жақын"        // -60 to -80
    case far       = "Алыс"         // < -80

    init(rssi: Int) {
        if rssi > -60      { self = .veryClose }
        else if rssi > -80 { self = .close }
        else               { self = .far }
    }
}

// MARK: - Discovered device

struct BLEDiscoveredDevice: Identifiable, Equatable {
    let id: String        // peripheral UUID string
    let name: String
    var rssi: Int
    let shortCode: String // "JNR-XXXXXXXX" → "XXXXXXXX"
    var distance: BLEDeviceDistance { BLEDeviceDistance(rssi: rssi) }
}

// MARK: - BLELinkingService

final class BLELinkingService: NSObject, ObservableObject {

    static let shared = BLELinkingService()

    @Published private(set) var discoveredDevices: [BLEDiscoveredDevice] = []
    @Published private(set) var isScanning      = false
    @Published private(set) var isAdvertising   = false
    @Published private(set) var centralState:   CBManagerState = .unknown
    @Published private(set) var peripheralState: CBManagerState = .unknown

    // Callbacks
    var onDeviceFound: ((BLEDiscoveredDevice) -> Void)?
    var onLinkAccepted: (() -> Void)?

    private var centralManager:    CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var ownShortCode = ""

    // MARK: - Setup

    private override init() {
        super.init()
    }

    private func ensureCentral() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    private func ensurePeripheral() {
        guard peripheralManager == nil else { return }
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    // MARK: - Parent side (advertise)

    /// Call on parent device. `uid` = Firebase UID.
    func startAdvertising(uid: String) {
        ownShortCode = String(uid.prefix(8)).uppercased()
        ensurePeripheral()
        guard peripheralManager?.state == .poweredOn else { return }
        _startAdvertisingIfReady()
    }

    private func _startAdvertisingIfReady() {
        guard let pm = peripheralManager, pm.state == .poweredOn else { return }
        pm.stopAdvertising()
        let svc = CBMutableService(type: kServiceUUID, primary: true)
        let char = CBMutableCharacteristic(
            type: kCharUUID,
            properties: [.read],
            value: ownShortCode.data(using: .utf8),
            permissions: .readable
        )
        svc.characteristics = [char]
        pm.add(svc)
        pm.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [kServiceUUID],
            CBAdvertisementDataLocalNameKey:    "\(kLocalNamePrefix)\(ownShortCode)"
        ])
        DispatchQueue.main.async { self.isAdvertising = true }
    }

    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        DispatchQueue.main.async { self.isAdvertising = false }
    }

    // MARK: - Child side (scan)

    func startScan() {
        ensureCentral()
        discoveredDevices.removeAll()
        guard centralManager?.state == .poweredOn else { return }
        centralManager?.scanForPeripherals(
            withServices: [kServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        DispatchQueue.main.async { self.isScanning = true }
    }

    func stopScan() {
        centralManager?.stopScan()
        DispatchQueue.main.async { self.isScanning = false }
    }

    /// Send link request via Firestore. Call after child taps discovered device.
    func sendLinkRequest(deviceShortCode: String, childUID: String) {
        Task {
            await FirestoreService.shared.sendBLELinkRequest(
                childUID: childUID,
                parentShortCode: deviceShortCode
            )
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLELinkingService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { self.centralState = central.state }
        if central.state == .poweredOn, isScanning {
            central.scanForPeripherals(withServices: [kServiceUUID],
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
              localName.hasPrefix(kLocalNamePrefix) else { return }
        let shortCode = String(localName.dropFirst(kLocalNamePrefix.count))
        let id = peripheral.identifier.uuidString
        let device = BLEDiscoveredDevice(
            id: id,
            name: localName,
            rssi: RSSI.intValue,
            shortCode: shortCode
        )
        DispatchQueue.main.async {
            if let idx = self.discoveredDevices.firstIndex(where: { $0.id == id }) {
                self.discoveredDevices[idx].rssi = RSSI.intValue
            } else {
                self.discoveredDevices.append(device)
                self.onDeviceFound?(device)
            }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLELinkingService: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        DispatchQueue.main.async { self.peripheralState = peripheral.state }
        if peripheral.state == .poweredOn, !ownShortCode.isEmpty {
            _startAdvertisingIfReady()
        }
    }
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        DispatchQueue.main.async { self.isAdvertising = error == nil }
    }
}

// MARK: - FirestoreService BLE extension (stub — add to FirestoreService.swift)

extension FirestoreService {
    func sendBLELinkRequest(childUID: String, parentShortCode: String) async {
        // Look up parent UID from shortCode stored at discoveryTokens/{shortCode}
        // Then create linkRequests/{requestId} document
        do {
            let tokenSnap = try await db.collection("discoveryTokens")
                .document(parentShortCode)
                .getDocument()
            guard let parentUID = tokenSnap.data()?["uid"] as? String else { return }

            let requestID = "\(childUID)_\(parentUID)"
            try await db.collection("linkRequests").document(requestID).setData([
                "childUid":  childUID,
                "parentUid": parentUID,
                "status":    "pending",
                "createdAt": Date().timeIntervalSince1970
            ])
        } catch {}
    }

    func publishDiscoveryToken(uid: String) async {
        let shortCode = String(uid.prefix(8)).uppercased()
        do {
            try await db.collection("discoveryTokens").document(shortCode).setData([
                "uid":       uid,
                "createdAt": Date().timeIntervalSince1970
            ])
        } catch {}
    }

    func acceptLinkRequest(requestID: String, parentUID: String, childUID: String) async {
        do {
            try await db.collection("linkRequests").document(requestID)
                .updateData(["status": "accepted"])
            try await db.collection("users").document(parentUID)
                .updateData(["children": [childUID]])   // merge later with arrayUnion via batch
            try await db.collection("users").document(childUID)
                .setData(["parentUid": parentUID, "isLinked": true], merge: true)
        } catch {}
    }
}
