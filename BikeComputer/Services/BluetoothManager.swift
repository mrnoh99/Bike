import Foundation
import CoreBluetooth

// MARK: - 표준 BLE GATT UUID

private enum GATT {
    // Cycling Speed and Cadence (CSC)
    static let cscService = CBUUID(string: "1816")
    static let cscMeasurement = CBUUID(string: "2A5B")
    // Heart Rate
    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    // 보조 정보
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    static let services = [cscService, heartRateService]
}

/// 센서가 제공하는 데이터 종류 (스크린샷의 Bike Speed / Bike Cadence / Heart Rate 구분).
enum SensorKind: String, Codable {
    case speed = "Bike Speed"
    case cadence = "Bike Cadence"
    case speedCadence = "Speed & Cadence"
    case heartRate = "Heart Rate"
    case unknown = "Sensor"
}

/// 발견·연결된 센서 1개를 표현하는 모델.
struct DiscoveredSensor: Identifiable, Equatable {
    let id: UUID                 // peripheral.identifier
    var name: String
    var kind: SensorKind
    var rssi: Int
    var isConnected: Bool
    var battery: Int?            // 0~100, 알 수 없으면 nil

    /// 마지막으로 읽은 즉정값 (cadence rpm 또는 wheel speed rpm 등 화면 표시용)
    var liveCadenceRPM: Int?
    var liveWheelRPM: Int?
}

/// CoreBluetooth 래퍼. 자전거 속도/케이던스(CSC)·심박수 센서를 스캔·연결하고
/// 실시간 측정값(속도 m/s, 케이던스 rpm, 심박수 bpm)을 발행한다.
final class BluetoothManager: NSObject, ObservableObject {

    // 화면에 보여줄 상태
    @Published private(set) var poweredOn = false
    @Published private(set) var isScanning = false
    @Published private(set) var sensors: [DiscoveredSensor] = []

    // 실시간 측정값 (RideSession 이 구독)
    @Published private(set) var wheelSpeedMetersPerSecond: Double?
    @Published private(set) var cadenceRPM: Int?
    @Published private(set) var heartRateBPM: Int?

    /// 속도 센서 → 거리 환산용 휠 둘레(미터). 700x25C ≈ 2.105 m 기본값.
    @Published var wheelCircumferenceMeters: Double = 2.105

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]

    // CSC 누적값 차분(differential) 계산용 직전 상태
    private var lastWheelRevs: UInt32?
    private var lastWheelEventTime: UInt16?
    private var lastCrankRevs: UInt16?
    private var lastCrankEventTime: UInt16?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "bikecomputer.central"])
    }

    // MARK: - 스캔 / 연결 제어

    func startScan() {
        guard poweredOn, !isScanning else { return }
        isScanning = true
        // 알려진 서비스만 스캔하되, 일부 센서가 광고에 서비스를 안 싣는 경우를 위해 nil 도 허용.
        central.scanForPeripherals(withServices: GATT.services,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
    }

    func connect(_ sensorID: UUID) {
        guard let p = peripherals[sensorID] else { return }
        central.connect(p, options: nil)
    }

    func disconnect(_ sensorID: UUID) {
        guard let p = peripherals[sensorID] else { return }
        central.cancelPeripheralConnection(p)
    }

    /// 새 라이딩 시작 시 차분 상태 초기화(이전 세션 값이 큰 점프로 잡히는 것 방지).
    func resetAccumulators() {
        lastWheelRevs = nil
        lastWheelEventTime = nil
        lastCrankRevs = nil
        lastCrankEventTime = nil
        wheelSpeedMetersPerSecond = nil
        cadenceRPM = nil
    }

    // MARK: - 내부 헬퍼

    private func upsertSensor(id: UUID, name: String, kind: SensorKind, rssi: Int, connected: Bool) {
        if let idx = sensors.firstIndex(where: { $0.id == id }) {
            sensors[idx].name = name
            if kind != .unknown { sensors[idx].kind = kind }
            sensors[idx].rssi = rssi
            sensors[idx].isConnected = connected
        } else {
            sensors.append(DiscoveredSensor(id: id, name: name, kind: kind, rssi: rssi,
                                            isConnected: connected, battery: nil,
                                            liveCadenceRPM: nil, liveWheelRPM: nil))
        }
        sensors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func setConnected(_ id: UUID, _ connected: Bool) {
        guard let idx = sensors.firstIndex(where: { $0.id == id }) else { return }
        sensors[idx].isConnected = connected
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        poweredOn = central.state == .poweredOn
        if !poweredOn { isScanning = false }
    }

    // 백그라운드 복원
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for p in restored {
                peripherals[p.identifier] = p
                p.delegate = self
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name ?? "알 수 없는 센서"
        let kind = inferKind(name: name, advertisementData: advertisementData)
        upsertSensor(id: peripheral.identifier, name: name, kind: kind,
                     rssi: RSSI.intValue, connected: peripheral.state == .connected)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(GATT.services + [GATT.batteryService])
        setConnected(peripheral.identifier, true)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        setConnected(peripheral.identifier, false)
        // 자동 재연결 시도
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        setConnected(peripheral.identifier, false)
    }

    private func inferKind(name: String, advertisementData: [String: Any]) -> SensorKind {
        let lower = name.lowercased()
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        if services.contains(GATT.heartRateService) || lower.contains("heart") || lower.contains("hr") {
            return .heartRate
        }
        if lower.contains("cadence") && lower.contains("speed") { return .speedCadence }
        if lower.contains("cadence") { return .cadence }
        if lower.contains("speed") { return .speed }
        if services.contains(GATT.cscService) { return .speedCadence }
        return .unknown
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case GATT.cscService:
                peripheral.discoverCharacteristics([GATT.cscMeasurement], for: service)
            case GATT.heartRateService:
                peripheral.discoverCharacteristics([GATT.heartRateMeasurement], for: service)
            case GATT.batteryService:
                peripheral.discoverCharacteristics([GATT.batteryLevel], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] {
            switch ch.uuid {
            case GATT.cscMeasurement, GATT.heartRateMeasurement:
                peripheral.setNotifyValue(true, for: ch)
            case GATT.batteryLevel:
                peripheral.readValue(for: ch)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case GATT.cscMeasurement:
            parseCSC(data, from: peripheral.identifier)
        case GATT.heartRateMeasurement:
            parseHeartRate(data)
        case GATT.batteryLevel:
            if let b = data.first, let idx = sensors.firstIndex(where: { $0.id == peripheral.identifier }) {
                sensors[idx].battery = Int(b)
            }
        default:
            break
        }
    }

    // MARK: 측정값 파서

    /// Heart Rate Measurement (0x2A37) 파싱. flags bit0: 0=uint8, 1=uint16.
    private func parseHeartRate(_ data: Data) {
        guard let flags = data.first else { return }
        let isUInt16 = (flags & 0x01) != 0
        var bpm = 0
        if isUInt16, data.count >= 3 {
            bpm = Int(data[1]) | (Int(data[2]) << 8)
        } else if data.count >= 2 {
            bpm = Int(data[1])
        }
        if bpm > 0 { heartRateBPM = bpm }
    }

    /// CSC Measurement (0x2A5B) 파싱.
    /// flags bit0: wheel rev 데이터 존재, bit1: crank rev 데이터 존재.
    /// 이벤트 시간 단위는 1/1024 초이며 16비트라 ~64초마다 wrap.
    private func parseCSC(_ data: Data, from id: UUID) {
        guard let flags = data.first else { return }
        let hasWheel = (flags & 0x01) != 0
        let hasCrank = (flags & 0x02) != 0
        var offset = 1
        let bytes = [UInt8](data)

        func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8) }
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i]) | (UInt32(bytes[i + 1]) << 8) | (UInt32(bytes[i + 2]) << 16) | (UInt32(bytes[i + 3]) << 24)
        }

        if hasWheel, bytes.count >= offset + 6 {
            let cumRevs = u32(offset); offset += 4
            let eventTime = u16(offset); offset += 2
            if let lastRevs = lastWheelRevs, let lastTime = lastWheelEventTime {
                let revDelta = cumRevs &- lastRevs
                let timeDelta = eventTime &- lastTime  // 1/1024 s, wrap 안전
                if timeDelta > 0 {
                    let seconds = Double(timeDelta) / 1024.0
                    let metersPerSecond = Double(revDelta) * wheelCircumferenceMeters / seconds
                    wheelSpeedMetersPerSecond = metersPerSecond
                    let rpm = Int((Double(revDelta) / seconds * 60).rounded())
                    updateLive(id) { $0.liveWheelRPM = rpm }
                } else if revDelta == 0 {
                    // 정지 (이벤트 시간 동일)
                    wheelSpeedMetersPerSecond = 0
                    updateLive(id) { $0.liveWheelRPM = 0 }
                }
            }
            lastWheelRevs = cumRevs
            lastWheelEventTime = eventTime
        }

        if hasCrank, bytes.count >= offset + 4 {
            let cumRevs = u16(offset); offset += 2
            let eventTime = u16(offset); offset += 2
            if let lastRevs = lastCrankRevs, let lastTime = lastCrankEventTime {
                let revDelta = cumRevs &- lastRevs
                let timeDelta = eventTime &- lastTime
                if timeDelta > 0 {
                    let seconds = Double(timeDelta) / 1024.0
                    let rpm = Int((Double(revDelta) / seconds * 60).rounded())
                    cadenceRPM = rpm
                    updateLive(id) { $0.liveCadenceRPM = rpm }
                } else if revDelta == 0 {
                    cadenceRPM = 0
                    updateLive(id) { $0.liveCadenceRPM = 0 }
                }
            }
            lastCrankRevs = cumRevs
            lastCrankEventTime = eventTime
        }
    }

    private func updateLive(_ id: UUID, _ mutate: (inout DiscoveredSensor) -> Void) {
        guard let idx = sensors.firstIndex(where: { $0.id == id }) else { return }
        mutate(&sensors[idx])
    }
}
