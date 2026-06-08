import SwiftUI

/// 대시보드 셀 하나: 작은 라벨 + 큰 숫자(+ 단위/보조값).
/// 스크린샷처럼 라벨은 회색 소문자 느낌, 값은 색상 강조.
struct MetricCell: View {
    let label: String
    let value: String
    var unit: String? = nil
    var subvalue: String? = nil
    var color: Color = Theme.value
    var valueSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.label)
                .tracking(0.5)
            Text(value)
                .font(Theme.metricFont(valueSize))
                .foregroundColor(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let unit {
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.label)
            } else if let subvalue {
                Text(subvalue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.label)
            } else {
                // 단위 줄 없을 때 높이 정렬용 여백
                Text(" ").font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
