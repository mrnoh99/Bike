import SwiftUI
import MapKit

/// Map 탭 — 현재 위치 + 진행 중인 라이딩 경로(폴리라인).
struct MapTabView: View {
    @EnvironmentObject var session: RideSession
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    @State private var showPastCourses = false

    var body: some View {
        ZStack(alignment: .top) {
            RouteMap(track: session.location.track,
                     userLocation: session.location.lastLocation?.coordinate,
                     region: $region)
                .ignoresSafeArea(edges: .top)

            // 상단 요약 바
            HStack(spacing: 20) {
                summary("거리", "\(String(format: "%.2f", session.displayDistance)) \(session.unit.distanceLabel)")
                summary("속도", "\(String(format: "%.1f", session.displaySpeed)) \(session.unit.speedLabel)")
                summary("시간", formatDuration(session.rideSeconds))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .overlay(alignment: .bottomTrailing) {
            Button { showPastCourses = true } label: {
                Label("과거 코스", systemImage: "map")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(16)
        }
        .sheet(isPresented: $showPastCourses) { PastCoursesMapView() }
    }

    private func summary(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.system(size: 15, weight: .bold))
        }
    }
}

/// UIKit MKMapView 래퍼 — 폴리라인 경로 표시.
/// `autoFit` 이 true 면 경로 전체가 보이도록 맞추고(상세 화면),
/// false 면 사용자 위치를 따라간다(라이딩 중 지도 탭).
struct RouteMap: UIViewRepresentable {
    let track: [CLLocationCoordinate2D]
    let userLocation: CLLocationCoordinate2D?
    @Binding var region: MKCoordinateRegion
    var autoFit: Bool = false

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        if !autoFit { map.userTrackingMode = .follow }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        guard track.count > 1 || userLocation != nil else { return }

        if track.count > 1 {
            let line = MKPolyline(coordinates: track, count: track.count)
            map.addOverlay(line)
            if autoFit {
                map.setVisibleMapRect(line.boundingMapRect,
                                      edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                                      animated: false)
                return
            }
        }
        if !autoFit, let loc = userLocation {
            let span = map.region.span.latitudeDelta > 0.2
                ? MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                : map.region.span
            map.setRegion(MKCoordinateRegion(center: loc, span: span), animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.strokeColor = UIColor.systemBlue
            r.lineWidth = 5
            return r
        }
    }
}
