import SwiftUI

/// Devices 탭 — 스크린샷 IMG_4261 재현. BLE 센서 스캔·연결 + 실시간 rpm 표시.
struct DevicesView: View {
    @EnvironmentObject var bluetooth: BluetoothManager
    @EnvironmentObject var session: RideSession

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(bluetooth.sensors) { sensor in
                        sensorRow(sensor)
                    }
                    if bluetooth.sensors.isEmpty {
                        Text(bluetooth.isScanning ? "센서를 찾는 중…" : "스캔을 시작하세요.")
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("속도·케이던스 센서는 애플워치 설정 > 블루투스에서 페어링하면 워치를 통해 측정됩니다. 아래 폰 BLE 센서 목록은 워치를 쓰지 않을 때의 폴백입니다(표준 CSC 0x1816·심박 0x180D).")
                }

                Section {
                    NavigationLink {
                        heartRateSettings
                    } label: {
                        Text("Heart Rate Monitor Settings")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(bluetooth.isScanning ? "중지" : "+ / Edit") {
                        bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                    }
                }
            }
            .onAppear { if bluetooth.poweredOn { bluetooth.startScan() } }
        }
    }

    private func sensorRow(_ s: DiscoveredSensor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.name).font(.system(size: 16, weight: .semibold))
                Spacer()
                if s.isConnected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.green)
                }
                if let b = s.battery {
                    Label("\(b)%", systemImage: "battery.50")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Text(s.id.uuidString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            // 센서 종류별 실시간 값
            HStack(spacing: 16) {
                Text(s.kind.rawValue).font(.caption).foregroundColor(Theme.blue)
                if let c = s.liveCadenceRPM { Text("Cadence: \(c) rpm").font(.caption).foregroundColor(.secondary) }
                if let w = s.liveWheelRPM { Text("Wheel Speed: \(w) rpm").font(.caption).foregroundColor(.secondary) }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            s.isConnected ? bluetooth.disconnect(s.id) : bluetooth.connect(s.id)
        }
    }

    private var heartRateSettings: some View {
        List {
            Section {
                HStack {
                    Label("Apple Watch", systemImage: "applewatch")
                    Spacer()
                    Text(session.watch.watchReachable ? "연결됨" : "대기 중")
                        .foregroundColor(session.watch.watchReachable ? Theme.green : .secondary)
                }
                if let bpm = session.watch.heartRateBPM {
                    HStack {
                        Text("워치 심박수")
                        Spacer()
                        Text("\(bpm) bpm").foregroundColor(Theme.red)
                    }
                }
            } header: {
                Text("기본 심박 측정")
            } footer: {
                Text("라이딩 Start 시 애플워치 앱이 자동 실행되어 심박수를 측정·전송합니다. 워치를 착용하고 폰과 페어링되어 있어야 합니다.")
            }

            Section("BLE 심박 스트랩 (선택)") {
                ForEach(bluetooth.sensors.filter { $0.kind == .heartRate }) { s in
                    HStack {
                        Text(s.name)
                        Spacer()
                        if s.isConnected { Image(systemName: "checkmark").foregroundColor(Theme.green) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { s.isConnected ? bluetooth.disconnect(s.id) : bluetooth.connect(s.id) }
                }
                if bluetooth.heartRateBPM != nil {
                    HStack {
                        Text("현재 심박수")
                        Spacer()
                        Text("\(bluetooth.heartRateBPM ?? 0) bpm").foregroundColor(Theme.red)
                    }
                }
            }
        }
        .navigationTitle("Heart Rate")
    }
}

#Preview {
    let session = RideSession.preview
    return DevicesView()
        .environmentObject(session.bluetooth)
        .environmentObject(session)
        .preferredColorScheme(.dark)
}
