import Foundation
import EventKit

/// 라이딩 종료(Done) 시 운동 요약을 iOS 캘린더에 이벤트로 기록한다.
/// 형식은 Cyclemeter 와 동일:
/// - 제목: "{자전거}, time {라이딩시간}, distance {거리} km"
/// - 위치: 경로명(라이딩 이름)
/// - 메모: Route / Ride Time / Stopped Time / Distance
/// - 시작·종료: 라이딩 시작 ~ 종료(총 경과)
final class CalendarLogger {
    private let store = EKEventStore()

    /// 라이딩 기록을 'bike' 캘린더(iCloud 우선)에 추가.
    /// 캘린더를 이름으로 찾으려면 목록 조회가 필요하므로 전체 접근 권한을 요청한다.
    func logRide(_ record: RideRecord, bikeName: String) {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            guard granted, let self else { return }
            self.createEvent(record, bikeName: bikeName)
        }
    }

    /// 제목이 "bike" 인 캘린더(iCloud/CalDAV 우선). 없으면 기본 캘린더.
    private func targetCalendar() -> EKCalendar? {
        let writable = store.calendars(for: .event).filter { $0.allowsContentModifications }
        let named = writable.filter { $0.title.caseInsensitiveCompare("bike") == .orderedSame }
        return named.first { $0.source.sourceType == .calDAV }   // iCloud 우선
            ?? named.first
            ?? store.defaultCalendarForNewEvents
    }

    private func createEvent(_ record: RideRecord, bikeName: String) {
        guard let calendar = targetCalendar() else { return }
        let km = record.distanceMeters / 1000.0
        let kmText = String(format: "%.2f", km)
        let rideTime = formatDuration(record.duration)                 // 예) 1:05:03
        let stopped = max(0, record.totalElapsed - record.duration)
        let stoppedText = formatDuration(stopped)                      // 예) 15:23

        let event = EKEvent(eventStore: store)
        event.title = "\(bikeName), time \(rideTime), distance \(kmText) km"
        event.location = record.name
        event.startDate = record.startedAt
        event.endDate = record.startedAt.addingTimeInterval(record.totalElapsed)
        event.notes = """
        Route: \(record.name)
        Ride Time: \(rideTime)
        Stopped Time: \(stoppedText)
        Distance: \(kmText) km
        """
        event.calendar = calendar
        try? store.save(event, span: .thisEvent)
    }
}
