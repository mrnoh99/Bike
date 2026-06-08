import Foundation
import HealthKit
import WatchConnectivity

/// 애플워치에서 측정한 실시간 심박수를 받는다.
/// - 라이딩 시작 시 `startWatchApp(toHandle:)` 로 워치의 사이클링 워크아웃을 띄우고,
/// - 워치 앱이 `WCSession` 으로 보내는 bpm 을 받아 발행한다.
final class HeartRateManager: NSObject, ObservableObject {
    @Published private(set) var heartRateBPM: Int?
    @Published private(set) var watchReachable = false
    @Published private(set) var authorized = false

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

    /// HealthKit 권한 요청(심박 읽기 + 워크아웃 공유). 워치 앱을 띄우려면 폰도 권한이 필요하다.
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable(),
              let hr = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let workout = HKObjectType.workoutType()
        healthStore.requestAuthorization(toShare: [workout], read: [hr, workout]) { [weak self] ok, _ in
            DispatchQueue.main.async { self?.authorized = ok }
        }
    }

    /// 라이딩 시작: 워치 앱을 실행해 사이클링 워크아웃을 시작시킨다.
    func startWatchWorkout() {
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
        guard let hr = message["hr"] as? Int else { return }
        DispatchQueue.main.async { self.heartRateBPM = hr > 0 ? hr : nil }
    }
}

extension HeartRateManager: WCSessionDelegate {
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
