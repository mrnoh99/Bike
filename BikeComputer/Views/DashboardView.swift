import SwiftUI

/// ⚙️ 메뉴로 이동하는 화면들.
enum DashDestination: String, Identifiable {
    case map, routes, devices, more
    var id: String { rawValue }
}

/// 메인(Stopwatch) 대시보드 — 스크린샷 IMG_4260 재현.
struct DashboardView: View {
    @EnvironmentObject var session: RideSession
    @State private var showSettings = false
    @State private var showAddCourse = false
    @State private var newCourseName = ""
    @State private var dest: DashDestination?

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
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $dest) { d in
            switch d {
            case .map: MapTabView()
            case .routes: RoutesView()
            case .devices: DevicesView()
            case .more: MoreView()
            }
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .alert("코스 추가", isPresented: $showAddCourse) {
            TextField("코스 이름 (예: 한강 라이딩)", text: $newCourseName)
            Button("추가") { session.addCourse(newCourseName) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("새 코스를 만들어 목록에 추가합니다.")
        }
        // 10분 미만 라이딩: 저장/삭제 선택
        .alert("10분 미만 라이딩", isPresented: Binding(
            get: { session.pendingShortRide != nil },
            set: { _ in })) {
            Button("저장") { session.savePendingRide() }
            Button("삭제", role: .destructive) { session.discardPendingRide() }
        } message: {
            Text("이 라이딩은 10분 미만입니다. 건강·캘린더·파일에 저장할까요?")
        }
        // 저장 완료 확인(건강·캘린더·파일 3가지)
        .alert("저장 완료", isPresented: Binding(
            get: { session.saveSummary != nil },
            set: { if !$0 { session.saveSummary = nil } })) {
            Button("확인") { session.saveSummary = nil }
        } message: {
            Text(session.saveSummary ?? "")
        }
    }

    // 상단 라벨 칩 (코스 풀다운 / 자전거 종류 풀다운)
    private var header: some View {
        HStack {
            courseMenu
            Spacer()
            bikeMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // 풀다운 칩 모양(텍스트 + ⌄)
    private func pulldownChip(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(white: 0.14)))
    }

    // 코스 풀다운(출근/퇴근 등 + 코스 추가)
    private var courseMenu: some View {
        Menu {
            ForEach(session.courses, id: \.self) { course in
                Button(course) { session.routeName = course }
            }
            Divider()
            Button("코스 추가…", systemImage: "plus") { newCourseName = ""; showAddCourse = true }
        } label: {
            pulldownChip(session.routeName)
        }
    }

    // 자전거 종류 풀다운(프리셋 3종 + 직접 입력)
    private var bikeMenu: some View {
        Menu {
            ForEach(RideSession.bikePresets, id: \.self) { name in
                Button(name) { session.bikeName = name }
            }
            Divider()
            Button("직접 입력…") { showSettings = true }
        } label: {
            pulldownChip(session.bikeName)
        }
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
                MetricCell(label: "Average", value: fmt(session.displayAverageSpeed, 2),
                           unit: session.unit.speedLabel, color: Theme.value, valueSize: 40)
            }
            divider
            row {
                MetricCell(label: "Ride", value: formatDuration(session.rideSeconds),
                           subvalue: formatDuration(session.movingSeconds), color: Theme.gold, valueSize: 40)
                MetricCell(label: "Total", value: formatDuration(session.totalSeconds),
                           color: Theme.gold, valueSize: 40)
            }
            divider
            // 심박: 현재 / 평균 / 최대
            row {
                MetricCell(label: "HR", value: session.heartRate.map(String.init) ?? "– – –",
                           unit: "bpm", color: Theme.red, valueSize: 34)
                MetricCell(label: "Mean", value: session.avgHeartRate.map(String.init) ?? "– – –",
                           unit: "bpm", color: Theme.red, valueSize: 26)
                MetricCell(label: "Max", value: session.maxHeartRate.map(String.init) ?? "– – –",
                           unit: "bpm", color: Theme.red, valueSize: 26)
            }
            divider
            // 케이던스: 현재 / 평균 / 최대
            row {
                MetricCell(label: "Cadence", value: session.cadence.map(String.init) ?? "– – –",
                           unit: "rpm", color: Theme.value, valueSize: 34)
                MetricCell(label: "Mean", value: session.avgCadence.map(String.init) ?? "– – –",
                           unit: "rpm", color: Theme.value, valueSize: 26)
                MetricCell(label: "Max", value: session.maxCadence.map(String.init) ?? "– – –",
                           unit: "rpm", color: Theme.value, valueSize: 26)
            }
            divider
            // 산소포화도: 최근 / 24h 최저 / 24h 최고 + 각 측정 시각(작은 글씨).
            row {
                MetricCell(label: "SpO2 최근",
                           value: session.spo2Percent.map { "\($0)%" } ?? "– – –",
                           subvalue: session.spo2LatestTimeText ?? " ",
                           color: Theme.cyan, valueSize: 30)
                MetricCell(label: "24h 최저",
                           value: session.spo2MinPercent.map { "\($0)%" } ?? "– – –",
                           subvalue: session.spo2MinTimeText ?? " ",
                           color: Theme.cyan, valueSize: 26)
                MetricCell(label: "24h 최고",
                           value: session.spo2MaxPercent.map { "\($0)%" } ?? "– – –",
                           subvalue: session.spo2MaxTimeText ?? " ",
                           color: Theme.cyan, valueSize: 26)
            }
            divider
            // 누적 거리 3종을 한 줄에. This Year/Total 은 큰 숫자라 작은 글씨로 표시.
            row {
                MetricCell(label: "This Month", value: fmt(session.thisMonthDistance, 0),
                           unit: session.unit.distanceLabel, color: Theme.purple, valueSize: 30)
                MetricCell(label: "This Year", value: fmt(session.thisYearDistance, 0),
                           unit: session.unit.distanceLabel, color: Theme.purple, valueSize: 22)
                MetricCell(label: "Total", value: fmt(session.totalDistance, 0),
                           unit: session.unit.distanceLabel, color: Theme.purple, valueSize: 22)
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
            // Done 은 일시정지(Stop 후) 상태에서만 Start 와 함께 표시. (running 중엔 Stop 혼자)
            if session.state == .paused {
                Button(action: { session.finish() }) {
                    Text("Done")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Capsule().fill(Theme.gray))
                }
            }

            Menu {
                Button { dest = .map } label: { Label("지도", systemImage: "map") }
                Button { dest = .routes } label: { Label("라이딩 기록", systemImage: "folder") }
                Button { dest = .devices } label: { Label("장치", systemImage: "dot.radiowaves.left.and.right") }
                Button { dest = .more } label: { Label("더보기 · 가져오기", systemImage: "ellipsis.circle") }
                Divider()
                Button { showSettings = true } label: { Label("라이딩 설정", systemImage: "slider.horizontal.3") }
            } label: {
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
        case .running: return "Stop"
        case .paused: return "Start"
        }
    }

    private var startColor: Color {
        session.state == .running ? Theme.red : Theme.green
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
            Text("Designed by Jaisung NOH MD 2026")
                .font(.system(size: 9))
                .foregroundColor(Theme.label)
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
                }
                Section("코스") {
                    ForEach(session.courses, id: \.self) { course in
                        Button {
                            session.routeName = course
                        } label: {
                            HStack {
                                Text(course).foregroundColor(.primary)
                                Spacer()
                                if session.routeName == course {
                                    Image(systemName: "checkmark").foregroundColor(Theme.gold)
                                }
                            }
                        }
                    }
                    .onDelete { session.removeCourse(at: $0) }
                    Button("코스 추가…", systemImage: "plus") { newCourseName = ""; showAddCourse = true }
                }
                Section("자전거 종류") {
                    Menu {
                        ForEach(RideSession.bikePresets, id: \.self) { name in
                            Button(name) { session.bikeName = name }
                        }
                    } label: {
                        HStack {
                            Text("종류 선택")
                            Spacer()
                            Text(session.bikeName).foregroundColor(.secondary)
                            Image(systemName: "chevron.up.chevron.down").foregroundColor(.secondary)
                        }
                    }
                    TextField("직접 입력", text: $session.bikeName)
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

#Preview {
    let session = RideSession.preview
    return DashboardView()
        .environmentObject(session)
        .environmentObject(session.bluetooth)
        .preferredColorScheme(.dark)
}
