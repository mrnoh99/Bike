import SwiftUI

/// 워치 화면 — 실시간 심박수 + 시작/정지. 아이폰 Start 로 자동 실행되지만
/// 워치에서 직접 시작할 수도 있다.
struct WatchContentView: View {
    @EnvironmentObject var workout: WorkoutManager

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)
                .font(.title3)
                .symbolEffect(.pulse, isActive: workout.isRunning)

            Text(workout.heartRate > 0 ? "\(workout.heartRate)" : "--")
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundColor(.red)
                .contentTransition(.numericText())

            Text("bpm")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                workout.isRunning ? workout.stopWorkout() : workout.startWorkout()
            } label: {
                Text(workout.isRunning ? "정지" : "시작")
                    .frame(maxWidth: .infinity)
            }
            .tint(workout.isRunning ? .red : .green)
            .padding(.top, 4)
        }
        .padding()
        .onAppear { workout.requestAuthorization() }
    }
}
