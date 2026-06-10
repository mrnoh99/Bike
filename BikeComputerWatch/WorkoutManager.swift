import Foundation
import HealthKit
import WatchConnectivity

/// 워치에서 사이클링 워크아웃 세션을 돌려 실시간 심박수·속도·케이던스를 수집하고,
/// `WCSession` 으로 아이폰에 전송한다. 속도·케이던스 BLE 센서는 워치 *설정 > 블루투스*
/// 에서 OS 에 페어링하면 HealthKit(`cyclingSpeed`/`cyclingCadence`)으로 들어온다.
final class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    @Published var heartRate: Int = 0
    @Published var isRunning = false

    /// 최근 산소포화도(%). 휴식 중 'SpO2 측정' 버튼으로 포착한 값.
    @Published var spo2: Int = 0
    /// SpO2 측정 대기(새 샘플 포착) 중인지.
    @Published var measuringSpO2 = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var spo2Query: HKQuery?

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

    /// HealthKit 권한 요청.
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        var share: Set<HKSampleType> = [HKObjectType.workoutType()]
        // 사이클링 속도·케이던스는 워치 설정에서 페어링한 BLE 센서를 OS 가 기록한다(watchOS 10+).
        let ids: [HKQuantityTypeIdentifier] = [.heartRate, .activeEnergyBurned, .distanceCycling,
                                               .cyclingSpeed, .cyclingCadence]
        for id in ids {
            if let t = HKQuantityType.quantityType(forIdentifier: id) {
                read.insert(t); share.insert(t)
            }
        }
        // 산소포화도는 읽기 전용(센서 트리거는 시스템 '혈중 산소' 앱/자동측정만 가능).
        if let spo2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            read.insert(spo2)
        }
        healthStore.requestAuthorization(toShare: share, read: read) { _, _ in }
    }

    // MARK: - 산소포화도(SpO2) 포착

    /// '측정' 버튼: 탭 이후 들어오는 새 SpO2 샘플을 포착해 폰으로 전송한다.
    /// 직접 센서를 켤 수는 없으므로, 사용자가 '혈중 산소' 앱에서 측정하거나
    /// watchOS 자동측정이 잡히면 그 값을 포착한다(60초 대기 후 자동 종료).
    func measureSpO2() {
        guard !measuringSpO2,
              let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }
        DispatchQueue.main.async { self.measuringSpO2 = true }

        fetchLatestSpO2()   // 대기 중 직전 최근값 우선 표시

        let tap = Date()
        let pred = HKQuery.predicateForSamples(withStart: tap, end: nil, options: .strictStartDate)
        let q = HKAnchoredObjectQuery(type: type, predicate: pred, anchor: nil,
                                      limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            self?.handleSpO2(samples, finishMeasuring: true)
        }
        q.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.handleSpO2(samples, finishMeasuring: true)
        }
        healthStore.execute(q)
        spo2Query = q

        // 타임아웃: 60초 내 새 측정이 없으면 대기 종료.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.stopMeasuringSpO2()
        }
    }

    private func fetchLatestSpO2() {
        guard let type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else { return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            self?.handleSpO2(samples, finishMeasuring: false)
        }
        healthStore.execute(q)
    }

    private func handleSpO2(_ samples: [HKSample]?, finishMeasuring: Bool) {
        guard let s = samples?.compactMap({ $0 as? HKQuantitySample })
            .max(by: { $0.endDate < $1.endDate }) else { return }
        let pct = s.quantity.doubleValue(for: .percent())   // 0~1
        DispatchQueue.main.async {
            self.spo2 = Int((pct * 100).rounded())
            if finishMeasuring { self.measuringSpO2 = false }
        }
        send(["spo2": pct, "spo2Date": s.endDate.timeIntervalSince1970])
        if finishMeasuring { stopMeasuringSpO2() }
    }

    private func stopMeasuringSpO2() {
        if let q = spo2Query { healthStore.stop(q); spo2Query = nil }
        DispatchQueue.main.async { self.measuringSpO2 = false }
    }

    /// 워크아웃 시작(아이폰의 startWatchApp 또는 워치 화면의 시작 버튼에서 호출).
    func startWorkout(configuration: HKWorkoutConfiguration? = nil) {
        guard !isRunning, HKHealthStore.isHealthDataAvailable() else { return }
        let config: HKWorkoutConfiguration = configuration ?? {
            let c = HKWorkoutConfiguration()
            c.activityType = .cycling
            c.locationType = .outdoor
            return c
        }()

        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let b = s.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            // 기본 수집(심박·거리·에너지) 외에 사이클링 속도·케이던스도 수집 활성화.
            for id in [HKQuantityTypeIdentifier.cyclingSpeed, .cyclingCadence] {
                if let t = HKQuantityType.quantityType(forIdentifier: id) {
                    dataSource.enableCollection(for: t, predicate: nil)
                }
            }
            b.dataSource = dataSource
            s.delegate = self
            b.delegate = self
            session = s
            builder = b

            let startDate = Date()
            s.startActivity(with: startDate)
            b.beginCollection(withStart: startDate) { _, _ in }
            DispatchQueue.main.async { self.isRunning = true }
        } catch {
            print("워크아웃 시작 실패: \(error)")
        }
    }

    /// 워크아웃 종료.
    func stopWorkout() {
        guard let session else { return }
        session.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        DispatchQueue.main.async {
            self.isRunning = false
            self.heartRate = 0
        }
    }

    /// 갱신된 센서 값(hr/speedMps/cadence 중 일부)을 폰으로 전송.
    private func send(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            try? s.updateApplicationContext(payload)
        }
    }
}

// MARK: - 워크아웃 세션/빌더 델리게이트

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended {
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.isRunning = false }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var payload: [String: Any] = [:]

        // 심박수 (count/min)
        if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           collectedTypes.contains(hrType),
           let q = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity() {
            let bpm = Int(q.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
            if bpm > 0 {
                payload["hr"] = bpm
                DispatchQueue.main.async { self.heartRate = bpm }
            }
        }

        // 사이클링 속도 (m/s) · 케이던스 (rpm) — 워치 설정에서 페어링한 센서값(watchOS 10+).
        if let spType = HKQuantityType.quantityType(forIdentifier: .cyclingSpeed),
           collectedTypes.contains(spType),
           let q = workoutBuilder.statistics(for: spType)?.mostRecentQuantity() {
            payload["speedMps"] = q.doubleValue(for: .meter().unitDivided(by: .second()))
        }
        if let cadType = HKQuantityType.quantityType(forIdentifier: .cyclingCadence),
           collectedTypes.contains(cadType),
           let q = workoutBuilder.statistics(for: cadType)?.mostRecentQuantity() {
            payload["cadence"] = Int(q.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
        }

        send(payload)
    }
}

// MARK: - 아이폰 명령 수신

extension WorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleCommand(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleCommand(applicationContext)
    }

    private func handleCommand(_ message: [String: Any]) {
        guard let cmd = message["command"] as? String else { return }
        DispatchQueue.main.async {
            switch cmd {
            case "start": self.startWorkout()
            case "stop": self.stopWorkout()
            default: break
            }
        }
    }
}
