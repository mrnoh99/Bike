import SwiftUI

/// 앱 진입점. 라이딩 세션(센서·GPS·통계)을 전역 상태로 주입한다.
@main
struct BikeComputerApp: App {
    @StateObject private var session = RideSession()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(session)
                .environmentObject(session.bluetooth)
                .preferredColorScheme(.dark)
        }
    }
}
