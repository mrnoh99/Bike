import Foundation
import Combine
import CoreLocation

/// 라이딩 상태 머신.
enum RideState {
    case idle       // 시작 전
    case running    // 라이딩 중
    case paused     // 일시정지
}

/// 현재 속도/케이던스의 출처. 우선순위: 워치 > 폰 BLE 센서 > GPS.
enum SpeedSource {
    case watch
    case bleSensor
    case gps
}

/// 대시보드의 모든 지표를 모으는 메인 뷰모델.
/// 블루투스 센서 + GPS 를 결합해 거리·속도·심박·케이던스를 계산하고,
/// 종료 시 RideStore 에 기록을 저장한다.
final class RideSession: ObservableObject {
    // 하위 서비스
    let bluetooth = BluetoothManager()
    let location = LocationManager()
    let store = RideStore()
    let watch = WatchSensorManager()   // 애플워치 심박·속도·케이던스
    let health = HealthStore()          // Apple Health 누적 거리 + 폰 단독 워크아웃 저장

    // 표시 단위
    @Published var unit: DistanceUnit = .kilometers

    // 라벨(스크린샷의 "1.출근길" / "6.Yeti" 자리)
    @Published var routeName: String = "1.라이딩"
    @Published var bikeName: String = "내 자전거"

    // 상태
    @Published private(set) var state: RideState = .idle
    @Published private(set) var clock: Date = Date()

    // 누적/계산 지표 (표시는 항상 단위 변환 후)
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var currentSpeedMps: Double = 0
    @Published private(set) var rideSeconds: TimeInterval = 0    // 라이딩 시간(정지 제외)
    @Published private(set) var totalSeconds: TimeInterval = 0   // 총 경과(시작~지금)
    @Published private(set) var maxSpeedMps: Double = 0
    @Published private(set) var movingSeconds: TimeInterval = 0  // 실제 움직인 시간(평균속도용)

    // 심박/케이던스
    @Published private(set) var heartRate: Int?
    @Published private(set) var maxHeartRate: Int?
    @Published private(set) var cadence: Int?
    @Published private(set) var maxCadence: Int?

    private var heartRateSamples: [Int] = []
    private var cadenceSamples: [Int] = []
    private var startedAt: Date?
    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    private let movingSpeedThresholdMps = 0.8  // 이 속도 이상이면 "움직이는 중"

    init() {
        // 시계 + 라이딩 타이머 (0.5초 간격)
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }

        // 속도: 워치(주) → 폰 BLE 센서 → GPS 순으로 수용(우선순위는 ingestSpeed 가 판정).
        watch.$watchSpeedMps
            .compactMap { $0 }
            .sink { [weak self] v in self?.ingestSpeed(v, fromSource: .watch) }
            .store(in: &cancellables)

        bluetooth.$wheelSpeedMetersPerSecond
            .compactMap { $0 }
            .sink { [weak self] v in self?.ingestSpeed(v, fromSource: .bleSensor) }
            .store(in: &cancellables)

        location.$gpsSpeedMetersPerSecond
            .sink { [weak self] v in self?.ingestSpeed(v, fromSource: .gps) }
            .store(in: &cancellables)

        // 케이던스: 워치(주) → 폰 BLE 센서.
        watch.$watchCadenceRPM
            .sink { [weak self] rpm in self?.ingestCadence(rpm, fromWatch: true) }
            .store(in: &cancellables)

        bluetooth.$cadenceRPM
            .sink { [weak self] rpm in self?.ingestCadence(rpm, fromWatch: false) }
            .store(in: &cancellables)

        // 심박수: 애플워치(주) + BLE 심박 스트랩(보조) 둘 다 수용.
        watch.$heartRateBPM
            .sink { [weak self] bpm in self?.ingestHeartRate(bpm) }
            .store(in: &cancellables)

        bluetooth.$heartRateBPM
            .sink { [weak self] bpm in self?.ingestHeartRate(bpm) }
            .store(in: &cancellables)

        // 중첩 ObservableObject 변경을 상위로 전달해 관련 뷰가 갱신되게 한다.
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        watch.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        health.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        location.requestAuthorization()
        watch.requestAuthorization()
        health.start()   // Apple Health 누적 거리 관찰 시작
    }

    // MARK: - 라이딩 제어 (Start / Pause / Done)

    func start() {
        switch state {
        case .idle:
            resetRide()
            startedAt = Date()
            bluetooth.resetAccumulators()
            location.startRecording()
            watch.startWatchWorkout()   // 워치 워크아웃(심박·속도·케이던스) 시작
            state = .running
        case .paused:
            location.resumeRecording()
            state = .running
        case .running:
            pause()
        }
    }

    func pause() {
        guard state == .running else { return }
        location.pauseRecording()
        state = .paused
    }

    /// "Done" — 라이딩 종료 후 기록 저장, idle 로 복귀.
    func finish() {
        guard state != .idle, let started = startedAt else {
            state = .idle
            return
        }
        location.stopRecording()
        let watchSavedWorkout = watch.didReceiveWatchDataThisRide
        watch.stopWatchWorkout()   // 워치 워크아웃 종료(워치가 HKWorkout 저장)

        let avgSpeed = movingSeconds > 1 ? distanceMeters / movingSeconds : 0

        let record = RideRecord(
            name: routeName,
            startedAt: started,
            duration: rideSeconds,
            totalElapsed: totalSeconds,
            distanceMeters: distanceMeters,
            averageSpeedMps: avgSpeed,
            maxSpeedMps: maxSpeedMps,
            maxHeartRate: maxHeartRate,
            avgHeartRate: avgHeartRate,
            maxCadence: maxCadence,
            track: location.track
        )
        // 의미 있는 라이딩만 저장 (10초 미만·0거리 제외).
        if distanceMeters > 5 || rideSeconds > 10 {
            store.add(record)   // 로컬 기록(목록·상세)
            // 워치 없이 탄 라이딩만 폰이 건강 앱에 저장(워치 사용 시 워치가 저장 → 이중 계산 방지).
            if !watchSavedWorkout {
                health.saveRide(record)
            }
        }
        health.refreshTotals()
        state = .idle
    }

    // MARK: - 표시용 계산값 (단위 변환)

    var displayDistance: Double { unit.distance(fromMeters: distanceMeters) }
    var displaySpeed: Double { unit.speed(fromMetersPerSecond: currentSpeedMps) }
    var displayMaxSpeed: Double { unit.speed(fromMetersPerSecond: maxSpeedMps) }
    var displayAverageSpeed: Double {
        guard movingSeconds > 1 else { return 0 }
        return unit.speed(fromMetersPerSecond: distanceMeters / movingSeconds)
    }
    // 누적 거리: Apple Health 기준(권한 허용 시), 미인증 시 로컬 기록으로 폴백.
    // 진행 중 라이딩은 아직 Health 미저장이므로 현재 거리(distanceMeters)를 더해 실시간 표시.
    var thisMonthDistance: Double {
        unit.distance(fromMeters: cumulative(health.thisMonthMeters, store.thisMonthMeters))
    }
    var thisYearDistance: Double {
        unit.distance(fromMeters: cumulative(health.thisYearMeters, store.thisYearMeters))
    }
    var totalDistance: Double {
        unit.distance(fromMeters: cumulative(health.totalMeters, store.totalMeters))
    }

    private func cumulative(_ healthMeters: Double, _ storeMeters: Double) -> Double {
        let base = health.hasHealthData ? healthMeters : storeMeters
        let inProgress = state == .idle ? 0 : distanceMeters
        return base + inProgress
    }

    /// 라이딩 중 평균 심박수(bpm). 표시용 누적 평균.
    var avgHeartRate: Int? {
        guard !heartRateSamples.isEmpty else { return nil }
        return Int((Double(heartRateSamples.reduce(0, +)) / Double(heartRateSamples.count)).rounded())
    }

    /// 라이딩 중 평균 케이던스(rpm). 표시용 누적 평균.
    var avgCadence: Int? {
        guard !cadenceSamples.isEmpty else { return nil }
        return Int((Double(cadenceSamples.reduce(0, +)) / Double(cadenceSamples.count)).rounded())
    }

    /// 최근 산소포화도 — 워치 'SpO2 측정' 버튼 값과 HealthKit 최근값 중 더 최신을 선택.
    /// (워치 버튼은 WCSession 으로 즉시 도착, HealthKit 은 동기화가 늦을 수 있음.)
    private var bestSpO2: (pct: Double, date: Date)? {
        let h: (Double, Date)? = health.latestSpO2.flatMap { v in health.latestSpO2Date.map { (v, $0) } }
        let w: (Double, Date)? = watch.spo2.flatMap { v in watch.spo2Date.map { (v, $0) } }
        switch (h, w) {
        case let (.some(a), .some(b)): return b.1 >= a.1 ? b : a
        case let (.some(a), nil): return a
        case let (nil, .some(b)): return b
        default: return nil
        }
    }

    /// 최근 산소포화도(%).
    var spo2Percent: Int? {
        bestSpO2.map { Int(($0.pct * 100).rounded()) }
    }

    /// 최근 SpO2 측정 경과 시간 표시("방금"/"12분 전"/"2시간 전"/"3일 전").
    var spo2AgeText: String? {
        guard let d = bestSpO2?.date else { return nil }
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "방금" }
        if s < 3600 { return "\(Int(s / 60))분 전" }
        if s < 86400 { return "\(Int(s / 3600))시간 전" }
        return "\(Int(s / 86400))일 전"
    }

    // MARK: - 내부

    private func tick() {
        clock = Date()
        guard state == .running, let started = startedAt else { return }
        totalSeconds = Date().timeIntervalSince(started)
        rideSeconds += 0.5
        if currentSpeedMps >= movingSpeedThresholdMps {
            movingSeconds += 0.5
        }
        // 거리는 항상 폰 GPS 기준(워치/BLE 속도는 표시용).
        distanceMeters = location.distanceMeters
    }

    private let speedFreshness: TimeInterval = 5   // 이 시간 내 값이면 "최근"으로 간주
    private var lastSpeedAt: [SpeedSource: Date] = [:]
    private var lastWatchCadenceAt: Date?

    private func isFresh(_ source: SpeedSource, _ now: Date) -> Bool {
        guard let t = lastSpeedAt[source] else { return false }
        return now.timeIntervalSince(t) <= speedFreshness
    }

    /// 속도 표시: 워치 > 폰 BLE 센서 > GPS. 상위 우선순위 소스가 최근 값을 보냈으면 하위는 무시.
    private func ingestSpeed(_ mps: Double, fromSource source: SpeedSource) {
        let now = Date()
        lastSpeedAt[source] = now
        switch source {
        case .gps where isFresh(.watch, now) || isFresh(.bleSensor, now):
            return
        case .bleSensor where isFresh(.watch, now):
            return
        default:
            break
        }
        currentSpeedMps = mps
        if mps > maxSpeedMps { maxSpeedMps = mps }
    }

    /// 케이던스 표시: 워치 우선, 워치 값이 최근이면 폰 BLE 값은 무시.
    private func ingestCadence(_ rpm: Int?, fromWatch: Bool) {
        let now = Date()
        if fromWatch {
            lastWatchCadenceAt = now
        } else if let t = lastWatchCadenceAt, now.timeIntervalSince(t) <= speedFreshness {
            return
        }
        cadence = rpm
        if let rpm, rpm > 0 {
            maxCadence = max(maxCadence ?? 0, rpm)
            if state == .running { cadenceSamples.append(rpm) }
        }
    }

    private func ingestHeartRate(_ bpm: Int?) {
        heartRate = bpm
        if let bpm, bpm > 0 {
            maxHeartRate = max(maxHeartRate ?? 0, bpm)
            if state == .running { heartRateSamples.append(bpm) }
        }
    }

    private func resetRide() {
        distanceMeters = 0
        currentSpeedMps = 0
        rideSeconds = 0
        totalSeconds = 0
        maxSpeedMps = 0
        movingSeconds = 0
        maxHeartRate = nil
        maxCadence = nil
        heartRateSamples = []
        cadenceSamples = []
    }
}

#if DEBUG
extension RideSession {
    /// SwiftUI 프리뷰용 더미 세션. 누적 통계/대시보드 값을 보기 위해 가짜 데이터를 채운다.
    static var preview: RideSession {
        let s = RideSession()
        s.routeName = "1.출근길"
        s.bikeName = "Yeti SB130"
        // 누적 통계용 더미 기록(Health 미인증 → store 폴백으로 표시됨).
        let now = Date()
        s.store.add(RideRecord(name: "어제 라이딩", startedAt: now.addingTimeInterval(-86_400),
                               duration: 3_600, totalElapsed: 3_900, distanceMeters: 24_500,
                               averageSpeedMps: 6.8, maxSpeedMps: 12.4, maxHeartRate: 168,
                               avgHeartRate: 142, maxCadence: 96, track: []))
        s.store.add(RideRecord(name: "주말 장거리", startedAt: now.addingTimeInterval(-6 * 86_400),
                               duration: 7_200, totalElapsed: 7_500, distanceMeters: 58_300,
                               averageSpeedMps: 8.1, maxSpeedMps: 15.2, maxHeartRate: 175,
                               avgHeartRate: 150, maxCadence: 102, track: []))
        // 라이브 표시값.
        s.distanceMeters = 12_340
        s.currentSpeedMps = 7.5
        s.maxSpeedMps = 13.9
        s.rideSeconds = 1_830
        s.totalSeconds = 1_980
        s.movingSeconds = 1_780
        s.heartRate = 148
        s.maxHeartRate = 165
        s.heartRateSamples = [138, 142, 145, 148, 150, 147]   // 평균 ≈ 145
        s.cadence = 88
        s.maxCadence = 97
        s.cadenceSamples = [80, 84, 86, 88, 90, 87]           // 평균 ≈ 86
        s.health.seedPreviewSpO2(percent: 98, at: Date().addingTimeInterval(-12 * 60))  // 12분 전
        return s
    }
}
#endif
