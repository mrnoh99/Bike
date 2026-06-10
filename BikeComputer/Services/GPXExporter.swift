import Foundation

/// 라이딩 경로를 GPX 파일로 내보낸다.
/// 저장 위치: **iCloud Drive > BikeCom > GPX** (앱 iCloud 컨테이너의 Documents/GPX).
/// iCloud 를 못 쓰면 로컬 Documents/GPX 로 폴백(Files 앱 > 나의 iPhone > Bike > GPX).
enum GPXExporter {

    /// 라이딩 1건을 GPX 로 저장한다. (iCloud 해석이 느릴 수 있어 백그라운드에서 수행)
    static func export(_ record: RideRecord) {
        guard !record.track.isEmpty else { return }
        let xml = makeGPX(record)
        let fileName = "\(fileStem(record)).gpx"
        DispatchQueue.global(qos: .utility).async {
            let dir = gpxFolder()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(fileName)
            let coordinator = NSFileCoordinator()
            var err: NSError?
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
                try? xml.data(using: .utf8)?.write(to: u, options: .atomic)
            }
        }
    }

    /// GPX 저장 폴더: iCloud 컨테이너(BikeCom)의 Documents/GPX, 없으면 로컬 Documents/GPX.
    static func gpxFolder() -> URL {
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return container.appendingPathComponent("Documents/GPX", isDirectory: true)
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("GPX", isDirectory: true)
    }

    // MARK: - GPX 생성

    private static func makeGPX(_ record: RideRecord) -> String {
        let iso = ISO8601DateFormatter()
        let n = record.track.count
        var points = ""
        for (i, c) in record.track.enumerated() {
            let t = record.startedAt.addingTimeInterval(record.totalElapsed * Double(i) / Double(max(1, n - 1)))
            points += "    <trkpt lat=\"\(c.lat)\" lon=\"\(c.lon)\"><time>\(iso.string(from: t))</time></trkpt>\n"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Bike Computer" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><time>\(iso.string(from: record.startedAt))</time></metadata>
          <trk>
            <name>\(escape(record.name))</name>
            <type>cycling</type>
            <trkseg>
        \(points)    </trkseg>
          </trk>
        </gpx>
        """
    }

    private static func fileStem(_ record: RideRecord) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        let safeName = record.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(safeName)-\(df.string(from: record.startedAt))"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
