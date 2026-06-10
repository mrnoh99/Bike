import SwiftUI
import MapKit

/// 라이딩 목록 정렬 기준.
enum RideSort: String, CaseIterable, Identifiable {
    case newest = "최신순"
    case oldest = "오래된순"
    case distance = "거리순"
    case duration = "시간순"
    var id: String { rawValue }

    func sorted(_ records: [RideRecord]) -> [RideRecord] {
        switch self {
        case .newest:   return records.sorted { $0.startedAt > $1.startedAt }
        case .oldest:   return records.sorted { $0.startedAt < $1.startedAt }
        case .distance: return records.sorted { $0.distanceMeters > $1.distanceMeters }
        case .duration: return records.sorted { $0.duration > $1.duration }
        }
    }
}

private let routeDateFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "yyyy.MM.dd HH:mm"; return f
}()

/// 목록 행(이름·거리·시간·날짜).
struct RideRow: View {
    let record: RideRecord
    let unit: DistanceUnit
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.name).font(.system(size: 16, weight: .semibold))
            HStack(spacing: 14) {
                Label(String(format: "%.2f %@", unit.distance(fromMeters: record.distanceMeters), unit.distanceLabel),
                      systemImage: "ruler")
                Label(formatDuration(record.duration), systemImage: "clock")
            }
            .font(.caption).foregroundColor(.secondary)
            Text(routeDateFormatter.string(from: record.startedAt))
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Routes 탭 — 저장된 라이딩 목록(정렬 변경 + 코스별 묶어보기) + 상세.
struct RoutesView: View {
    @EnvironmentObject var session: RideSession
    @State private var sort: RideSort = .newest
    @State private var grouped = false

    var body: some View {
        NavigationView {
            Group {
                if session.store.records.isEmpty {
                    emptyState
                } else if grouped {
                    groupedList
                } else {
                    flatList
                }
            }
            .navigationTitle("Routes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("정렬", selection: $sort) {
                            ForEach(RideSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Divider()
                        Toggle("코스별 보기", isOn: $grouped)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        List {
            Text("아직 저장된 라이딩이 없습니다.\nStopwatch 에서 Start 후 Done 을 누르면 기록됩니다.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // 평면 목록(정렬 적용)
    private var flatList: some View {
        let records = sort.sorted(session.store.records)
        return List {
            ForEach(records) { record in
                NavigationLink {
                    RideDetailView(record: record, unit: session.unit)
                } label: {
                    RideRow(record: record, unit: session.unit)
                }
            }
            .onDelete { idx in
                idx.map { records[$0] }.forEach { session.store.delete($0) }
            }
        }
    }

    // 코스별 묶음(시작/끝 GPS + 거리로 분류)
    private var groupedList: some View {
        List {
            ForEach(RouteGrouping.groups(session.store.records)) { group in
                NavigationLink {
                    RouteGroupView(group: group, sort: sort)
                } label: {
                    groupRow(group)
                }
            }
        }
    }

    private func groupRow(_ g: RouteGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(g.title).font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(g.rides.count)회")
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 14) {
                Label(String(format: "평균 %.1f km", g.averageMeters / 1000), systemImage: "ruler")
                Label(String(format: "합계 %.0f km", g.totalMeters / 1000), systemImage: "sum")
            }
            .font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// 한 코스에 묶인 라이딩 목록.
struct RouteGroupView: View {
    @EnvironmentObject var session: RideSession
    let group: RouteGroup
    let sort: RideSort

    var body: some View {
        List {
            ForEach(sort.sorted(group.rides)) { record in
                NavigationLink {
                    RideDetailView(record: record, unit: session.unit)
                } label: {
                    RideRow(record: record, unit: session.unit)
                }
            }
            .onDelete { idx in
                let arr = sort.sorted(group.rides)
                idx.map { arr[$0] }.forEach { session.store.delete($0) }
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 코스 분류 (시작 GPS + 끝 GPS + 거리)

struct RouteGroup: Identifiable {
    let id: String
    var title: String
    var rides: [RideRecord]
    var totalMeters: Double { rides.reduce(0) { $0 + $1.distanceMeters } }
    var averageMeters: Double { rides.isEmpty ? 0 : totalMeters / Double(rides.count) }
}

enum RouteGrouping {
    /// 시작 좌표(≈110m)·끝 좌표(≈110m)·거리(1km 버킷)가 같으면 같은 코스로 본다.
    static func groups(_ records: [RideRecord]) -> [RouteGroup] {
        var buckets: [String: [RideRecord]] = [:]
        var noGPS: [RideRecord] = []
        for r in records {
            if let key = signature(r) {
                buckets[key, default: []].append(r)
            } else {
                noGPS.append(r)
            }
        }
        var result = buckets.map { key, rides -> RouteGroup in
            RouteGroup(id: key, title: title(for: rides), rides: rides)
        }
        // 자주 탄 코스 먼저.
        result.sort { $0.rides.count > $1.rides.count }
        if !noGPS.isEmpty {
            result.append(RouteGroup(id: "no-gps", title: "경로 없음", rides: noGPS))
        }
        return result
    }

    private static func signature(_ r: RideRecord) -> String? {
        guard let s = r.track.first, let e = r.track.last else { return nil }
        let sk = String(format: "%.3f,%.3f", s.lat, s.lon)
        let ek = String(format: "%.3f,%.3f", e.lat, e.lon)
        let dk = Int((r.distanceMeters / 1000).rounded())
        return "\(sk)|\(ek)|\(dk)km"
    }

    /// 그룹 제목 = 가장 많이 쓰인 라이딩 이름.
    private static func title(for rides: [RideRecord]) -> String {
        var counts: [String: Int] = [:]
        for r in rides { counts[r.name, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? "코스"
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
