import Foundation
import HealthKit
import WatchConnectivity

/// 애플워치에서 측정한 실시간 센서값(심박수·속도·케이던스)을 받는다.
/// - 라이딩 시작 시 `startWatchApp(toHandle:)` 로 워치의 사이클링 워크아웃을 띄우고,
/// - 워치 앱이 `WCSession` 으로 보내는 값(`hr`/`speedMps`/`cadence`)을 받아 발행한다.
///
/// 속도·케이던스 BLE 센서는 워치 *설정 > 블루투스* 에서 OS 에 페어링하면
/// 워치 워크아웃의 HealthKit(`cyclingSpeed`/`cyclingCadence`)으로 들어오고, 그 값을 폰에 중계한다.
final class WatchSensorManager: NSObject, ObservableObject {
    @Published private(set) var heartRateBPM: Int?
    @Published private(set) var watchSpeedMps: Double?
    @Published private(set) var watchCadenceRPM: Int?
    @Published private(set) var watchReachable = false
    @Published private(set) var authorized = false

    /// 이번 라이딩에서 워치로부터 데이터를 한 번이라도 받았는지.
    /// (false 이면 폰 단독 라이딩으로 보고 폰이 HealthKit 워크아웃을 저장한다.)
    private(set) var didReceiveWatchDataThisRide = false

    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// HealthKit 권한 요청(심박·사이클링 거리 읽기 + 워크아웃·거리 공유).
    /// 워치 앱을 띄우려면, 그리고 폰 단독 라이딩을 건강 앱에 저장하려면 폰도 권한이 필요하다.
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workout = HKObjectType.workoutType()
        var read: Set<HKObjectType> = [workout]
        var share: Set<HKSampleType> = [workout]
        for id in [HKQuantityTypeIdentifier.heartRate, .distanceCycling] {
            if let t = HKQuantityType.quantityType(forIdentifier: id) {
                read.insert(t); share.insert(t)
            }
        }
        // 산소포화도(SpO2)는 읽기 전용 — 워치가 백그라운드로 기록한 최근 값을 표시.
        if let spo2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            read.insert(spo2)
        }
        healthStore.requestAuthorization(toShare: share, read: read) { [weak self] ok, _ in
            DispatchQueue.main.async { self?.authorized = ok }
        }
    }

    /// 라이딩 시작: 워치 앱을 실행해 사이클링 워크아웃을 시작시킨다.
    func startWatchWorkout() {
        didReceiveWatchDataThisRide = false
        watchSpeedMps = nil
        watchCadenceRPM = nil
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor
        healthStore.startWatchApp(toHandle: config) { _, _ in }
        send(["command": "start"])
    }

    /// 라이딩 종료: 워치 워크아웃을 멈춘다.
    func stopWatchWorkout() {
        heartRateBPM = nil
        watchSpeedMps = nil
        watchCadenceRPM = nil
        send(["command": "stop"])
    }

    private func send(_ payload: [String: Any]) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? s.updateApplicationContext(payload)
        }
    }

    private func handle(_ message: [String: Any]) {
        // 명령 에코 등 센서값이 없는 메시지는 무시.
        let hasSensorData = message["hr"] != nil || message["speedMps"] != nil || message["cadence"] != nil
        guard hasSensorData else { return }
        DispatchQueue.main.async {
            self.didReceiveWatchDataThisRide = true
            if let hr = message["hr"] as? Int {
                self.heartRateBPM = hr > 0 ? hr : nil
            }
            if let v = message["speedMps"] as? Double {
                self.watchSpeedMps = v >= 0 ? v : nil
            }
            if let rpm = message["cadence"] as? Int {
                self.watchCadenceRPM = rpm >= 0 ? rpm : nil
            }
        }
    }
}

extension WatchSensorManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.watchReachable = session.isReachable }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.watchReachable = session.isReachable }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }
}
