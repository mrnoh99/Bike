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
                        Text(session.watch.watchReachable ? "Apple Watch 연결됨" : "Apple Watch")
                            .foregroundColor(session.watch.watchReachable ? Theme.green : .secondary)
                    }
                    HStack {
                        Text("워치 속도")
                        Spacer()
                        Text(session.watch.watchSpeedMps.map { String(format: "%.1f %@", session.unit.speed(fromMetersPerSecond: $0), session.unit.speedLabel) } ?? "수신 대기")
                            .foregroundColor(session.watch.watchSpeedMps != nil ? Theme.green : .secondary)
                    }
                    HStack {
                        Text("워치 케이던스")
                        Spacer()
                        Text(session.watch.watchCadenceRPM.map { "\($0) rpm" } ?? "수신 대기")
                            .foregroundColor(session.watch.watchCadenceRPM != nil ? Theme.green : .secondary)
                    }
                }
                Section {
                    HStack { Text("버전"); Spacer(); Text("1.0").foregroundColor(.secondary) }
                } footer: {
                    Text("속도·케이던스는 애플워치에 페어링한 BLE 센서(워치 설정 > 블루투스)를 통해 받고, 워치가 없을 때만 폰이 직접 BLE(CSC, 0x1816)·GPS 로 측정합니다. 라이딩은 Apple 건강 앱에 운동으로 기록되며 누적 거리는 건강 데이터 기준입니다.")
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

#Preview {
    let session = RideSession.preview
    return MoreView()
        .environmentObject(session)
        .environmentObject(session.bluetooth)
        .preferredColorScheme(.dark)
}
