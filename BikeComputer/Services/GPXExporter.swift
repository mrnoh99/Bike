import Foundation

/// 라이딩 경로를 GPX 파일로 내보낸다.
/// 저장 위치: 앱 Documents 의 **GPX 폴더** — Info.plist 의 파일 공유 설정으로
/// **Files 앱 > 나의 iPhone > Bike > GPX** 에서 보거나 공유할 수 있다.
enum GPXExporter {

    /// 고정 폴더: <Documents>/GPX (없으면 생성)
    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("GPX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 라이딩 1건을 GPX 로 저장하고 파일 URL 을 반환한다.
    @discardableResult
    static func export(_ record: RideRecord) -> URL? {
        guard !record.track.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        let n = record.track.count
        var points = ""
        for (i, c) in record.track.enumerated() {
            let t = record.startedAt.addingTimeInterval(record.totalElapsed * Double(i) / Double(max(1, n - 1)))
            points += "    <trkpt lat=\"\(c.lat)\" lon=\"\(c.lon)\"><time>\(iso.string(from: t))</time></trkpt>\n"
        }

        let xml = """
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

        let url = folder.appendingPathComponent("\(fileStem(record)).gpx")
        try? xml.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
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
