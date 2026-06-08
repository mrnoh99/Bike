import Foundation
import CoreLocation

/// 완료된 라이딩 1건. Routes 탭과 누적 통계(이번달/올해/총) 계산에 쓰인다.
struct RideRecord: Identifiable, Codable {
    let id: UUID
    var name: String
    var startedAt: Date
    var duration: TimeInterval        // 실제 라이딩 시간(정지 제외)
    var totalElapsed: TimeInterval     // 시작~종료 총 경과
    var distanceMeters: Double
    var averageSpeedMps: Double
    var maxSpeedMps: Double
    var maxHeartRate: Int?
    var avgHeartRate: Int?
    var maxCadence: Int?
    /// 경로 좌표(저장 시 압축을 위해 위/경도 쌍 배열).
    var track: [Coordinate]

    struct Coordinate: Codable {
        var lat: Double
        var lon: Double
        var clCoordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    }

    init(id: UUID = UUID(), name: String, startedAt: Date, duration: TimeInterval,
         totalElapsed: TimeInterval, distanceMeters: Double, averageSpeedMps: Double,
         maxSpeedMps: Double, maxHeartRate: Int?, avgHeartRate: Int?, maxCadence: Int?,
         track: [CLLocationCoordinate2D]) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.duration = duration
        self.totalElapsed = totalElapsed
        self.distanceMeters = distanceMeters
        self.averageSpeedMps = averageSpeedMps
        self.maxSpeedMps = maxSpeedMps
        self.maxHeartRate = maxHeartRate
        self.avgHeartRate = avgHeartRate
        self.maxCadence = maxCadence
        self.track = track.map { Coordinate(lat: $0.latitude, lon: $0.longitude) }
    }
}

/// 라이딩 기록 저장소 + 누적 거리 통계. JSON 파일로 영속화한다.
final class RideStore: ObservableObject {
    @Published private(set) var records: [RideRecord] = []

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("rides.json")
        load()
    }

    func add(_ record: RideRecord) {
        records.insert(record, at: 0)
        save()
    }

    func delete(_ record: RideRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    // MARK: 누적 거리(미터)

    var thisMonthMeters: Double {
        let cal = Calendar.current
        return records.filter { cal.isDate($0.startedAt, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.distanceMeters }
    }

    var thisYearMeters: Double {
        let cal = Calendar.current
        return records.filter { cal.isDate($0.startedAt, equalTo: Date(), toGranularity: .year) }
            .reduce(0) { $0 + $1.distanceMeters }
    }

    var totalMeters: Double {
        records.reduce(0) { $0 + $1.distanceMeters }
    }

    // MARK: 영속화

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([RideRecord].self, from: data) {
            records = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
