import SwiftUI

/// 워치 주행화면 — Apple 피트니스 '실외 자전거' 스타일.
/// 1) 현재 시각  2) 심박수  3) 속도(+연결등)  4) 케이던스(+연결등)  5) 시작/정지.
struct WatchContentView: View {
    @EnvironmentObject var workout: WorkoutManager

    var body: some View {
        TabView {
            workoutPage
            spo2Page
        }
        .tabViewStyle(.verticalPage)
        .onAppear { workout.requestAuthorization() }
    }

    private var workoutPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                // 1) 현재 시각 (1초마다 갱신)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: 4) {
                        Image(systemName: "figure.outdoor.cycle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                        Text(Self.clock.string(from: ctx.date))
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }

                divider

                // 2) 심박수
                MetricRow(value: workout.heartRate > 0 ? "\(workout.heartRate)" : "--",
                          unit: "BPM", label: "심박수",
                          color: .fitnessRed, icon: "heart.fill", light: nil,
                          pulsing: workout.isRunning)

                divider

                // 3) 속도 + 연결등
                MetricRow(value: workout.speedMps > 0 ? String(format: "%.1f", workout.speedMps * 3.6) : "--",
                          unit: "KM/H", label: "속도",
                          color: .fitnessGreen, icon: "speedometer",
                          light: workout.speedSensorConnected)

                divider

                // 4) 케이던스 + 연결등
                MetricRow(value: workout.cadenceRPM > 0 ? "\(workout.cadenceRPM)" : "--",
                          unit: "RPM", label: "케이던스",
                          color: .fitnessGreen, icon: "arrow.triangle.2.circlepath",
                          light: workout.cadenceSensorConnected)

                // 5) CONNECT/DISCONNECT (폰으로 데이터 송신 시작/중지)
                Button {
                    workout.isRunning ? workout.stopWorkout() : workout.startWorkout()
                } label: {
                    Text(workout.isRunning ? "DISCONNECT" : "CONNECT")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .tint(workout.isRunning ? .red : .green)
                .padding(.top, 6)

                Text("Developed by JaiSung NOH MD 2026")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    private var spo2Page: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "lungs.fill").foregroundColor(.cyan)
                Text(workout.spo2 > 0 ? "SpO₂ \(workout.spo2)%" : "SpO₂ --")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.cyan)
            }
            Button { workout.measureSpO2() } label: {
                Label(workout.measuringSpO2 ? "측정 대기…" : "SpO₂ 측정", systemImage: "lungs.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.cyan)
            .disabled(workout.measuringSpO2)
            Spacer(minLength: 0)
        }
        .padding()
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
    }

    static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

private extension Color {
    static let fitnessRed = Color(red: 1.0, green: 0.32, blue: 0.36)    // 심박
    static let fitnessGreen = Color(red: 0.62, green: 0.86, blue: 0.20) // 속도·케이던스(피트니스 연두)
}

/// 피트니스 스타일 메트릭 한 줄 — 큰 색 숫자 + 작은 단위 + 라벨(+ 아이콘/연결등).
private struct MetricRow: View {
    let value: String
    let unit: String?
    let label: String
    let color: Color
    let icon: String?
    /// nil 이면 연결등 없음. true=연결(초록), false=대기(회색).
    let light: Bool?
    var pulsing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(color)
                        .symbolEffect(.pulse, options: .repeating, isActive: pulsing)
                }
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                if let light {
                    // 연결등을 하트 아이콘과 같은 크기로 확대.
                    Circle()
                        .fill(light ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 18, height: 18)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
