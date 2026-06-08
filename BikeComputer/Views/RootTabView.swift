import SwiftUI

/// 하단 탭바 — Stopwatch · Map · Routes · Devices · More (스크린샷과 동일).
struct RootTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Stopwatch", systemImage: "stopwatch") }

            MapTabView()
                .tabItem { Label("Map", systemImage: "map") }

            RoutesView()
                .tabItem { Label("Routes", systemImage: "folder") }

            DevicesView()
                .tabItem { Label("Devices", systemImage: "dot.radiowaves.left.and.right") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .tint(Theme.gold)
    }
}
