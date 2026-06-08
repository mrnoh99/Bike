import Foundation
import Combine
import CoreLocation

/// 라이딩 상태 머신.
enum RideState {
    case idle       // 시작 전
    case running    // 라이딩 중
    case paused     // 일시정지
}

/// 대시보드의 모든 지표를 모으는 메인 뷰모델.
/// 블루투스 센서 + GPS 를 결합해 거리·속도·심박·케이던스를 계산하고,
/// 종료 시 RideStore 에 기록을 저장한다.
final class RideSession: ObservableObject {
    // 하위 서비스
    let bluetooth = BluetoothManager()
    let location = LocationManager()
    let store = RideStore()

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
    private var startedAt: Date?
    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    private let movingSpeedThresholdMps = 0.8  // 이 속도 이상이면 "움직이는 중"

    init() {
        // 시계 + 라이딩 타이머 (0.5초 간격)
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }

        // 센서/GPS 측정값 구독
        bluetooth.$wheelSpeedMetersPerSecond
            .compactMap { $0 }
            .sink { [weak self] v in self?.ingestSpeed(v, fromSensor: true) }
            .store(in: &cancellables)

        bluetooth.$cadenceRPM
            .sink { [weak self] rpm in self?.ingestCadence(rpm) }
            .store(in: &cancellables)

        bluetooth.$heartRateBPM
            .sink { [weak self] bpm in self?.ingestHeartRate(bpm) }
            .store(in: &cancellables)

        location.$gpsSpeedMetersPerSecond
            .sink { [weak self] v in self?.ingestSpeed(v, fromSensor: false) }
            .store(in: &cancellables)

        // 중첩 ObservableObject(기록 저장소) 변경을 상위로 전달해 Routes/More 뷰가 갱신되게 한다.
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        location.requestAuthorization()
    }

    // MARK: - 라이딩 제어 (Start / Pause / Done)

    func start() {
        switch state {
        case .idle:
            resetRide()
            startedAt = Date()
            bluetooth.resetAccumulators()
            location.startRecording()
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

        let avgSpeed = movingSeconds > 1 ? distanceMeters / movingSeconds : 0
        let avgHR = heartRateSamples.isEmpty ? nil
            : Int((Double(heartRateSamples.reduce(0, +)) / Double(heartRateSamples.count)).rounded())

        let record = RideRecord(
            name: routeName,
            startedAt: started,
            duration: rideSeconds,
            totalElapsed: totalSeconds,
            distanceMeters: distanceMeters,
            averageSpeedMps: avgSpeed,
            maxSpeedMps: maxSpeedMps,
            maxHeartRate: maxHeartRate,
            avgHeartRate: avgHR,
            maxCadence: maxCadence,
            track: location.track
        )
        // 의미 있는 라이딩만 저장 (10초 미만·0거리 제외).
        if distanceMeters > 5 || rideSeconds > 10 {
            store.add(record)
        }
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
    var thisMonthDistance: Double { unit.distance(fromMeters: store.thisMonthMeters + distanceMeters) }
    var thisYearDistance: Double { unit.distance(fromMeters: store.thisYearMeters + distanceMeters) }
    var totalDistance: Double { unit.distance(fromMeters: store.totalMeters + distanceMeters) }

    // MARK: - 내부

    private func tick() {
        clock = Date()
        guard state == .running, let started = startedAt else { return }
        totalSeconds = Date().timeIntervalSince(started)
        rideSeconds += 0.5
        if currentSpeedMps >= movingSpeedThresholdMps {
            movingSeconds += 0.5
        }
        // GPS 거리를 라이딩 거리에 반영(속도 센서 미연결 시 주 거리원).
        if !hasSpeedSensor {
            distanceMeters = location.distanceMeters
        }
    }

    /// 속도 센서가 최근 값을 보냈는지(센서 우선).
    private var hasSpeedSensor: Bool {
        bluetooth.wheelSpeedMetersPerSecond != nil
    }

    private func ingestSpeed(_ mps: Double, fromSensor: Bool) {
        // 센서가 있으면 센서 속도 우선, 없으면 GPS.
        if fromSensor || !hasSpeedSensor {
            currentSpeedMps = mps
            if mps > maxSpeedMps { maxSpeedMps = mps }
        }
        // 속도 센서로 거리 적산 (running 중에만).
        if fromSensor, state == .running {
            // 0.5초 tick 과 별개로 센서 콜백 기반 적산은 GPS 로 대체하므로 생략.
            // 센서 속도 + GPS 거리를 함께 쓰되 거리 기준은 GPS(track) 우선.
            distanceMeters = max(distanceMeters, location.distanceMeters)
        }
    }

    private func ingestCadence(_ rpm: Int?) {
        cadence = rpm
        if let rpm, rpm > 0 {
            maxCadence = max(maxCadence ?? 0, rpm)
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
    }
}
