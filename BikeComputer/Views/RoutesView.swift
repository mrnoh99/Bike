import SwiftUI
import MapKit

/// Routes 탭 — 저장된 라이딩 기록 목록 + 상세.
struct RoutesView: View {
    @EnvironmentObject var session: RideSession

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy.MM.dd HH:mm"; return f
    }()

    var body: some View {
        NavigationView {
            List {
                if session.store.records.isEmpty {
                    Text("아직 저장된 라이딩이 없습니다.\nStopwatch 에서 Start 후 Done 을 누르면 기록됩니다.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(session.store.records) { record in
                    NavigationLink {
                        RideDetailView(record: record, unit: session.unit)
                    } label: {
                        row(record)
                    }
                }
                .onDelete { idx in
                    idx.map { session.store.records[$0] }.forEach { session.store.delete($0) }
                }
            }
            .navigationTitle("Routes")
        }
    }

    private func row(_ r: RideRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.name).font(.system(size: 16, weight: .semibold))
            HStack(spacing: 14) {
                Label(String(format: "%.2f %@", session.unit.distance(fromMeters: r.distanceMeters), session.unit.distanceLabel),
                      systemImage: "ruler")
                Label(formatDuration(r.duration), systemImage: "clock")
            }
            .font(.caption).foregroundColor(.secondary)
            Text(dateFormatter.string(from: r.startedAt))
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// 라이딩 상세 — 지도 + 핵심 지표.
struct RideDetailView: View {
    let record: RideRecord
    let unit: DistanceUnit
    @State private var gpxURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RouteMap(track: record.track.map { $0.clCoordinate },
                         userLocation: record.track.first?.clCoordinate,
                         region: .constant(MKCoordinateRegion()),
                         autoFit: true)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    stat("거리", String(format: "%.2f %@", unit.distance(fromMeters: record.distanceMeters), unit.distanceLabel), Theme.gold)
                    stat("라이딩 시간", formatDuration(record.duration), Theme.gold)
                    stat("평균 속도", String(format: "%.1f %@", unit.speed(fromMetersPerSecond: record.averageSpeedMps), unit.speedLabel), Theme.value)
                    stat("최고 속도", String(format: "%.1f %@", unit.speed(fromMetersPerSecond: record.maxSpeedMps), unit.speedLabel), Theme.blue)
                    stat("최대 심박", record.maxHeartRate.map { "\($0) bpm" } ?? "–", Theme.red)
                    stat("평균 심박", record.avgHeartRate.map { "\($0) bpm" } ?? "–", Theme.red)
                    stat("최대 케이던스", record.maxCadence.map { "\($0) rpm" } ?? "–", Theme.value)
                    stat("총 경과", formatDuration(record.totalElapsed), Theme.value)
                }
                .padding(.horizontal)

                if let gpxURL {
                    ShareLink(item: gpxURL) {
                        Label("GPX 공유", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color(white: 0.14), in: Capsule())
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let gpxURL {
                ShareLink(item: gpxURL) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .onAppear { if gpxURL == nil { gpxURL = GPXExporter.writeTempGPX(record) } }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
