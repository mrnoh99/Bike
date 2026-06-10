import Foundation
import HealthKit

/// 폰 측 Apple Health 연동.
/// - 누적 거리(이번달/올해/총)를 건강 앱의 **모든 사이클링 거리(`distanceCycling`)** 합에서 읽는다.
///   → 앱 설치 전·다른 기기(워치 등)로 탄 기록까지 포함되고, 재설치해도 유지된다.
/// - 워치 없이 폰 단독으로 탄 라이딩은 폰이 직접 HKWorkout 으로 저장한다.
///   (워치 사용 시에는 워치가 워크아웃을 저장하므로 폰은 저장하지 않아 이중 계산을 막는다.)
///
/// HealthKit 권한은 `WatchSensorManager.requestAuthorization()` 에서 함께 요청한다
/// (workout·distanceCycling 공유/읽기). 별도 프롬프트를 띄우지 않는다.
final class HealthStore: ObservableObject {
    @Published private(set) var thisMonthMeters: Double = 0
    @Published private(set) var thisYearMeters: Double = 0
    @Published private(set) var totalMeters: Double = 0

    /// 건강 권한이 허용되어 누적값을 읽어온 적이 있는지(폴백 판정용).
    @Published private(set) var hasHealthData = false

    /// 가장 최근 산소포화도(0~1 비율)와 그 측정 시각.
    /// watchOS 가 백그라운드로 기록한 값 — 실시간 연속 측정은 불가(운동 중 모션으로 측정도 드묾).
    @Published private(set) var latestSpO2: Double?
    @Published private(set) var latestSpO2Date: Date?

    private let healthStore = HKHealthStore()
    private var distanceType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .distanceCycling)
    }
    private var spo2Type: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)
    }
    private var observer: HKObserverQuery?
    private var spo2Observer: HKObserverQuery?

    /// 관찰 시작 + 첫 집계. 새 운동(워치 포함)이 저장되면 자동 재집계한다.
    func start() {
        refreshTotals()
        refreshSpO2()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if observer == nil, let type = distanceType {
            let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                self?.refreshTotals()
                completion()
            }
            observer = q
            healthStore.execute(q)
        }
        // 새 SpO2 측정이 들어오면 자동 갱신.
        if spo2Observer == nil, let type = spo2Type {
            let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                self?.refreshSpO2()
                completion()
            }
            spo2Observer = q
            healthStore.execute(q)
        }
    }

    /// 가장 최근 산소포화도 1건을 읽어 발행한다.
    func refreshSpO2() {
        guard HKHealthStore.isHealthDataAvailable(), let type = spo2Type else { return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let s = samples?.first as? HKQuantitySample else { return }
            let pct = s.quantity.doubleValue(for: .percent())   // 0~1
            DispatchQueue.main.async {
                self?.latestSpO2 = pct
                self?.latestSpO2Date = s.endDate
            }
        }
        healthStore.execute(q)
    }

    /// 이번달/올해/총 사이클링 거리(미터)를 다시 집계한다.
    func refreshTotals() {
        guard HKHealthStore.isHealthDataAvailable(), distanceType != nil else { return }
        let cal = Calendar.current
        let now = Date()
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        let yearStart = cal.dateInterval(of: .year, for: now)?.start ?? now

        sum(from: monthStart, to: now) { [weak self] m in self?.set(\.thisMonthMeters, m) }
        sum(from: yearStart, to: now) { [weak self] m in self?.set(\.thisYearMeters, m) }
        sum(from: nil, to: now) { [weak self] m in self?.set(\.totalMeters, m) }
    }

    private func set(_ key: ReferenceWritableKeyPath<HealthStore, Double>, _ value: Double) {
        DispatchQueue.main.async {
            self[keyPath: key] = value
            self.hasHealthData = true
        }
    }

    private func sum(from start: Date?, to end: Date, completion: @escaping (Double) -> Void) {
        guard let type = distanceType else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                  options: .cumulativeSum) { _, stats, _ in
            let meters = stats?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
            completion(meters)
        }
        healthStore.execute(q)
    }

    /// 폰 단독 라이딩을 건강 앱에 사이클링 워크아웃으로 저장한다.
    func saveRide(_ record: RideRecord) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        let start = record.startedAt
        let end = start.addingTimeInterval(record.totalElapsed)

        builder.beginCollection(withStart: start) { [weak self] ok, _ in
            guard ok else { return }
            let finish = {
                builder.endCollection(withEnd: end) { _, _ in
                    builder.finishWorkout { _, _ in
                        DispatchQueue.main.async { self?.refreshTotals() }
                    }
                }
            }
            if record.distanceMeters > 0,
               let type = HKQuantityType.quantityType(forIdentifier: .distanceCycling) {
                let quantity = HKQuantity(unit: .meter(), doubleValue: record.distanceMeters)
                let sample = HKQuantitySample(type: type, quantity: quantity, start: start, end: end)
                builder.add([sample]) { _, _ in finish() }
            } else {
                finish()
            }
        }
    }

    #if DEBUG
    /// SwiftUI 프리뷰용 — 최근 SpO2 값 주입.
    func seedPreviewSpO2(percent: Double, at date: Date) {
        latestSpO2 = percent / 100
        latestSpO2Date = date
    }
    #endif
}
