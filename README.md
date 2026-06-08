# Bike Computer (iOS)

아이폰용 자전거 컴퓨터 앱. **GPS**로 속도·거리·경로를 기록하고, **블루투스(BLE) 센서**로
속도·케이던스·심박수를 측정한다. Cyclemeter 스타일의 대시보드 UI를 SwiftUI 로 구현했다.

## 화면 (하단 탭)

| 탭 | 내용 |
|----|------|
| **Stopwatch** | 메인 대시보드 — 시계 / 거리 / 속도 / 평균속도 / 라이딩·총 시간 / 심박·최대심박 / 케이던스 / 이번달·올해·누적 거리 + **Start / Done** |
| **Map** | 현재 위치 + 진행 중 경로(폴리라인) |
| **Routes** | 저장된 라이딩 기록 목록·상세(지도+지표) |
| **Devices** | BLE 센서 스캔·연결, 실시간 rpm·심박, 심박계 설정 |
| **More** | 단위(km/mi), 이름, 누적 통계, 센서/권한 상태 |

## 측정 방식

- **속도·거리**: 속도 센서(CSC) 연결 시 휠 둘레 기반 계산, 없으면 **GPS**(CoreLocation).
- **케이던스**: CSC 크랭크 회전수 차분 → rpm.
- **심박수**: 표준 Heart Rate 센서(0x180D), bpm.
- 백그라운드에서도 블루투스·위치 계속 기록(`UIBackgroundModes`).

### 지원 BLE 프로토콜 (표준 GATT)

| 서비스 | UUID | 특성 |
|--------|------|------|
| Cycling Speed and Cadence | `0x1816` | CSC Measurement `0x2A5B` |
| Heart Rate | `0x180D` | HR Measurement `0x2A37` |
| Battery | `0x180F` | Battery Level `0x2A19` |

스크린샷의 Wahoo / CYCPLUS / Magene 등 대부분의 시판 속도·케이던스·심박 센서가 이 표준을 따른다.

## 빌드

이 저장소는 `.xcodeproj` 대신 **XcodeGen** `project.yml` 로 프로젝트를 정의한다.

```bash
brew install xcodegen      # 최초 1회
xcodegen generate          # project.yml → BikeComputer.xcodeproj 생성
open BikeComputer.xcodeproj # Xcode 에서 실 기기로 실행
```

> 블루투스·GPS 는 **실제 기기**에서만 동작한다(시뮬레이터 불가). 서명 팀(`DEVELOPMENT_TEAM`)을
> Xcode 의 Signing & Capabilities 에서 본인 계정으로 지정한 뒤 실행한다.

## 구조

```
BikeComputer/
  App/        BikeComputerApp.swift · Info.plist
  Design/     Theme.swift                 # 색상·폰트 토큰
  Models/     Units.swift · RideRecord.swift(+RideStore)
  Services/   BluetoothManager.swift      # CoreBluetooth: CSC·심박 파싱
              LocationManager.swift       # CoreLocation: GPS 속도·거리·트랙
              RideSession.swift           # 메인 뷰모델(상태머신·통계·저장)
  Views/      RootTabView · DashboardView · MapTabView · RoutesView
              DevicesView · MoreView · Components/MetricCell
  Assets.xcassets
```

## 현재 한계 / 다음 단계

- 라이딩 거리는 GPS 트랙 기준이 우선이며, 속도 센서 단독 거리 적산은 GPS 가 없을 때 보강 예정.
- HealthKit 연동(애플워치 심박) · GPX 내보내기 · 랩(구간) 기록 · 사용자 자전거 다중 프로필 미구현.
- 앱 아이콘 이미지 미포함(placeholder).
