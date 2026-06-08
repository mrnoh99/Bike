import SwiftUI

/// 앱의 루트 뷰. 하단 탭(Stopwatch·Map·Routes·Devices·More)을 담는다.
struct ContentView: View {
    var body: some View {
        RootTabView()
    }
}

#Preview {
    let session = RideSession()
    return ContentView()
        .environmentObject(session)
        .environmentObject(session.bluetooth)
        .preferredColorScheme(.dark)
}
