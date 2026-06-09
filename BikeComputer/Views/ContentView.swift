import SwiftUI

/// 앱의 루트 뷰. 하단 탭(Stopwatch·Map·Routes·Devices·More)을 담는다.
struct ContentView: View {
    var body: some View {
        RootTabView()
    }
}

// 캔버스(Resume)에서 더미 데이터가 채워진 전체 앱 목업을 볼 수 있다.
// 첫 탭(Stopwatch)에 대시보드의 거리·속도·심박·케이던스·누적 통계가 표시된다.
#Preview("앱 전체 (목업 데이터)") {
    let session = RideSession.preview
    return ContentView()
        .environmentObject(session)
        .environmentObject(session.bluetooth)
        .preferredColorScheme(.dark)
}

// 실제 빈 상태(시작 전)를 보고 싶을 때.
#Preview("앱 전체 (빈 상태)") {
    let session = RideSession()
    return ContentView()
        .environmentObject(session)
        .environmentObject(session.bluetooth)
        .preferredColorScheme(.dark)
}
