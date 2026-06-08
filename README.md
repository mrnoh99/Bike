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
- **심박수**: **애플워치**가 기본. (BLE 심박 스트랩 0x180D 도 보조 지원)
- 백그라운드에서도 블루투스·위치 계속 기록(`UIBackgroundModes`).

### 애플워치 심박 측정 (watchOS 컴패니언 앱)

라이딩 **Start** → 아이폰이 `HKHealthStore.startWatchApp(toHandle:)` 로 워치 앱을 자동 실행
→ 워치가 `HKWorkoutSession` + `HKLiveWorkoutBuilder` 로 실시간 심박을 수집
→ `WatchConnectivity(WCSession)` 로 bpm 을 아이폰에 전송 → 대시보드 Heart Rate 에 표시.
**Done** 시 워치 워크아웃 종료. 워치를 착용하고 폰과 페어링되어 있어야 한다.

```
아이폰 RideSession.start()
   └─ HeartRateManager.startWatchWorkout()  ─ startWatchApp(toHandle:) ─▶  워치 앱 실행
                                                                            └─ WorkoutManager
                                                                                 HKLiveWorkoutBuilder(심박)
아이폰 HeartRateManager  ◀── WCSession {"hr": 142} ──────────────────────────────┘
```

### 지원 BLE 프로토콜 (표준 GATT)

| 서비스 | UUID | 특성 |
|--------|------|------|
| Cycling Speed and Cadence | `0x1816` | CSC Measurement `0x2A5B` |
| Heart Rate | `0x180D` | HR Measurement `0x2A37` |
| Battery | `0x180F` | Battery Level `0x2A19` |

스크린샷의 Wahoo / CYCPLUS / Magene 등 대부분의 시판 속도·케이던스 센서가 이 표준을 따른다.
(심박수는 애플워치를 기본으로 사용하며, BLE 심박 스트랩은 선택 보조 수단이다.)

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
BikeComputer/                       # 아이폰 앱
  App/        BikeComputerApp.swift · ContentView · Info.plist · *.entitlements
  Design/     Theme.swift                 # 색상·폰트 토큰
  Models/     Units.swift · RideRecord.swift(+RideStore)
  Services/   BluetoothManager.swift      # CoreBluetooth: CSC(속도·케이던스) 파싱
              LocationManager.swift       # CoreLocation: GPS 속도·거리·트랙
              HeartRateManager.swift      # HealthKit + WCSession: 워치 심박 수신
              RideSession.swift           # 메인 뷰모델(상태머신·통계·저장)
  Views/      RootTabView · DashboardView · MapTabView · RoutesView
              DevicesView · MoreView · Components/MetricCell
  Assets.xcassets

BikeComputerWatch/                  # 애플워치 앱
  BikeComputerWatchApp.swift          # @main + WKApplicationDelegate(handle workout)
  WatchContentView.swift              # 실시간 심박 화면 + 시작/정지
  WorkoutManager.swift                # HKWorkoutSession·HKLiveWorkoutBuilder → WCSession 전송
  Info.plist · *.entitlements · Assets.xcassets
```

> 워치 앱은 아이폰 앱에 **임베드**되어 함께 설치된다(`project.yml` 의 `embed: true`).
> 두 타깃 모두 **HealthKit Capability** 와 서명 팀이 필요하다(Xcode Signing & Capabilities).

## 현재 한계 / 다음 단계

- 라이딩 거리는 GPS 트랙 기준이 우선이며, 속도 센서 단독 거리 적산은 GPS 가 없을 때 보강 예정.
- GPX 내보내기 · 랩(구간) 기록 · 사용자 자전거 다중 프로필 미구현.
- 앱 아이콘 이미지 미포함(placeholder, 폰·워치 공통).
- `startWatchApp(toHandle:)` 는 워치 앱이 설치되어 있어야 동작. 워치에서 직접 **시작** 버튼으로도 측정 가능.
