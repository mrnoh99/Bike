import SwiftUI

/// More 탭 — 단위·센서·정보 등 기타 설정.
struct MoreView: View {
    @EnvironmentObject var session: RideSession

    var body: some View {
        NavigationView {
            List {
                Section("표시 단위") {
                    Picker("거리/속도", selection: $session.unit) {
                        Text("킬로미터 (km/h)").tag(DistanceUnit.kilometers)
                        Text("마일 (mph)").tag(DistanceUnit.miles)
                    }
                }
                Section("라이딩") {
                    HStack { Text("라이딩 이름"); Spacer(); TextField("", text: $session.routeName).multilineTextAlignment(.trailing) }
                    HStack { Text("자전거"); Spacer(); TextField("", text: $session.bikeName).multilineTextAlignment(.trailing) }
                }
                Section("누적 통계") {
                    statRow("이번 달", session.thisMonthDistance)
                    statRow("올해", session.thisYearDistance)
                    statRow("전체", session.totalDistance)
                    HStack { Text("총 라이딩 수"); Spacer(); Text("\(session.store.records.count)").foregroundColor(.secondary) }
                }
                Section("센서") {
                    HStack {
                        Text("블루투스")
                        Spacer()
                        Text(session.bluetooth.poweredOn ? "켜짐" : "꺼짐")
                            .foregroundColor(session.bluetooth.poweredOn ? Theme.green : Theme.red)
                    }
                    HStack {
                        Text("위치 권한")
                        Spacer()
                        Text(session.location.authorized ? "허용됨" : "필요")
                            .foregroundColor(session.location.authorized ? Theme.green : Theme.red)
                    }
                    HStack {
                        Text("심박 측정")
                        Spacer()
                        Text(session.heartRateManager.watchReachable ? "Apple Watch 연결됨" : "Apple Watch")
                            .foregroundColor(session.heartRateManager.watchReachable ? Theme.green : .secondary)
                    }
                }
                Section {
                    HStack { Text("버전"); Spacer(); Text("1.0").foregroundColor(.secondary) }
                } footer: {
                    Text("표준 BLE 속도·케이던스(CSC, 0x1816)·심박수(0x180D) 센서와 GPS 를 사용합니다.")
                }
            }
            .navigationTitle("More")
        }
    }

    private func statRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.0f %@", value, session.unit.distanceLabel)).foregroundColor(Theme.purple)
        }
    }
}
