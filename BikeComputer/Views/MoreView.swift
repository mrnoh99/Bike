import SwiftUI
import UniformTypeIdentifiers

/// More 탭 — 센서·정보·데이터 가져오기 등 기타 설정.
struct MoreView: View {
    @EnvironmentObject var session: RideSession
    @State private var showImporter = false

    private var gpxTypes: [UTType] {
        [UTType(filenameExtension: "gpx") ?? .xml, .xml, .folder]
    }

    var body: some View {
        NavigationView {
            List {
                Section("라이딩") {
                    HStack { Text("라이딩 이름"); Spacer(); TextField("", text: $session.routeName).multilineTextAlignment(.trailing) }
                }
                Section("자전거 종류") {
                    Menu {
                        ForEach(RideSession.bikePresets, id: \.self) { name in
                            Button(name) { session.bikeName = name }
                        }
                    } label: {
                        HStack {
                            Text("종류")
                            Spacer()
                            Text(session.bikeName).foregroundColor(.secondary)
                            Image(systemName: "chevron.up.chevron.down").foregroundColor(.secondary)
                        }
                    }
                    TextField("직접 입력", text: $session.bikeName)
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
                    Button {
                        session.importStatus = nil
                        showImporter = true
                    } label: {
                        Label("Cyclemeter GPX 가져오기", systemImage: "square.and.arrow.down")
                    }
                    if let status = session.importStatus {
                        Text(status).font(.caption).foregroundColor(.secondary)
                    }
                } header: {
                    Text("데이터 가져오기")
                } footer: {
                    Text("Cyclemeter 에서 라이딩을 GPX 로 내보낸 뒤, 여러 .gpx 파일이나 폴더를 통째로 선택하면 일괄로 가져옵니다(경로·심박·케이던스·속도 포함). 같은 시작 시각의 기록은 중복 제외됩니다.")
                }
                Section {
                    HStack { Text("버전"); Spacer(); Text("1.0").foregroundColor(.secondary) }
                    HStack { Text("디자인"); Spacer(); Text("Designed by Jaisung NOH MD 2026").foregroundColor(.secondary) }
                } footer: {
                    Text("속도·케이던스는 애플워치에 페어링한 BLE 센서(워치 설정 > 블루투스)를 통해 받고, 워치가 없을 때만 폰이 직접 BLE(CSC, 0x1816)·GPS 로 측정합니다. 라이딩은 Apple 건강 앱에 운동으로 기록되며 누적 거리는 건강 데이터 기준입니다.")
                }
            }
            .navigationTitle("More")
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: gpxTypes,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { session.importGPX(from: urls) }
            }
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
