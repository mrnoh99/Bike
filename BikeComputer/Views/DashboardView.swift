import SwiftUI

/// 메인(Stopwatch) 대시보드 — 스크린샷 IMG_4260 재현.
struct DashboardView: View {
    @EnvironmentObject var session: RideSession
    @State private var showSettings = false

    private let clockFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                grid
            }
            controls
            gpsBar
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showSettings) { settingsSheet }
    }

    // 상단 라벨 칩 두 개 (라이딩 이름 / 자전거 이름)
    private var header: some View {
        HStack {
            chip(session.routeName)
            Spacer()
            chip(session.bikeName)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color(white: 0.14)))
    }

    // 2열 메트릭 그리드
    private var grid: some View {
        VStack(spacing: 0) {
            row {
                MetricCell(label: "Clock", value: clockFormatter.string(from: session.clock).prefix5,
                           color: Theme.value, valueSize: 44)
                MetricCell(label: "Distance", value: fmt(session.displayDistance, 2),
                           unit: session.unit.distanceLabel, color: Theme.gold, valueSize: 44)
            }
            divider
            row {
                MetricCell(label: "Speed", value: fmt(session.displaySpeed, 2),
                           unit: session.unit.speedLabel, color: Theme.blue, valueSize: 40)
                MetricCell(label: "Average Speed", value: fmt(session.displayAverageSpeed, 2),
                           unit: session.unit.speedLabel, color: Theme.value, valueSize: 40)
            }
            divider
            row {
                MetricCell(label: "Ride Time", value: formatDuration(session.rideSeconds),
                           subvalue: formatDuration(session.movingSeconds), color: Theme.gold, valueSize: 40)
                MetricCell(label: "Total Time", value: formatDuration(session.totalSeconds),
                           color: Theme.gold, valueSize: 40)
            }
            divider
            row {
                MetricCell(label: "Heart Rate", value: session.heartRate.map(String.init) ?? "– – –",
                           unit: "bpm", color: Theme.red, valueSize: 38)
                MetricCell(label: "Max Heart Rate", value: session.maxHeartRate.map(String.init) ?? "– – –",
                           unit: "bpm", color: Theme.red, valueSize: 38)
            }
            divider
            row {
                MetricCell(label: "Cycle Cadence", value: session.cadence.map(String.init) ?? "– – –",
                           unit: "rpm", color: Theme.value, valueSize: 38)
                MetricCell(label: "This Month", value: fmt(session.thisMonthDistance, 0),
                           unit: session.unit.distanceLabel, color: Theme.purple, valueSize: 38)
            }
            divider
            row {
                MetricCell(label: "This Year", value: fmt(session.thisYearDistance, 0),
                           unit: session.unit.distanceLabel, color: Theme.purple, valueSize: 40)
                MetricCell(label: "Total", value: fmt(session.totalDistance, 0),
                           unit: session.unit.distanceLabel, color: Theme.purple, valueSize: 40)
            }
        }
        .padding(.horizontal, 8)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
    }

    private var divider: some View {
        Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.horizontal, 8)
    }

    // Start / Done 버튼 + 설정 기어
    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: { session.start() }) {
                Text(startLabel)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Capsule().fill(startColor))
            }
            Button(action: { session.finish() }) {
                Text("Done")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Capsule().fill(Theme.gray))
            }
            .disabled(session.state == .idle)
            .opacity(session.state == .idle ? 0.5 : 1)

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Theme.gold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var startLabel: String {
        switch session.state {
        case .idle: return "Start"
        case .running: return "Pause"
        case .paused: return "Resume"
        }
    }

    private var startColor: Color {
        session.state == .running ? Theme.gold : Theme.green
    }

    // GPS 정확도 표시줄
    private var gpsBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 11))
                .foregroundColor(gpsColor)
            Text("GPS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.label)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var gpsColor: Color {
        let acc = session.location.horizontalAccuracy
        if acc < 0 { return Theme.gray }
        if acc <= 10 { return Theme.green }
        if acc <= 30 { return Theme.gold }
        return Theme.red
    }

    // 설정 시트 (라벨·단위·휠 둘레)
    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section("이름") {
                    TextField("라이딩 이름", text: $session.routeName)
                    TextField("자전거 이름", text: $session.bikeName)
                }
                Section("단위") {
                    Picker("거리 단위", selection: $session.unit) {
                        Text("킬로미터 (km)").tag(DistanceUnit.kilometers)
                        Text("마일 (mi)").tag(DistanceUnit.miles)
                    }
                }
                Section("속도 센서") {
                    HStack {
                        Text("휠 둘레")
                        Spacer()
                        Text("\(session.bluetooth.wheelCircumferenceMeters, specifier: "%.3f") m")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $session.bluetooth.wheelCircumferenceMeters, in: 1.5...2.4, step: 0.005)
                    Text("700×25C ≈ 2.105 m · 700×28C ≈ 2.136 m")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func fmt(_ v: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", v)
    }
}

private extension String {
    /// "HH:mm:ss" → "HH:mm" (스크린샷의 시계 표기)
    var prefix5: String { String(prefix(5)) }
}
