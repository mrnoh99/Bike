#!/usr/bin/env bash
# BikeComputer — iPhone + Watch companion 설치 (연동용)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
XCODEBUILD="${DEVELOPER_DIR}/usr/bin/xcodebuild"
DEVICECTL="${DEVELOPER_DIR}/usr/bin/devicectl"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "❌ xcodegen 필요: brew install xcodegen"
  exit 1
fi

echo "==> 1. 프로젝트 생성"
xcodegen generate
./scripts/prune_watch_scheme.sh

DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
  echo ""
  echo "연결된 iPhone:"
  xcrun xctrace list devices 2>/dev/null | grep -E 'iPhone' | grep -v Simulator || true
  if [[ -x "$DEVICECTL" ]]; then
    echo ""
    echo "CoreDevice (devicectl):"
    "$DEVICECTL" list devices 2>/dev/null | grep -i iphone | grep -v unavailable || true
  fi
  echo ""
  echo "사용법: ./scripts/install_device.sh <iPhone-UDID>"
  echo "예: ./scripts/install_device.sh 00008101-000D30842E9A001E"
  exit 1
fi

echo "==> 2. 빌드 + iPhone 설치 (Watch companion 번들 포함)"
"$XCODEBUILD" \
  -project BikeComputer.xcodeproj \
  -scheme BikeComputer \
  -destination "id=${DEVICE_ID}" \
  -configuration Debug \
  -allowProvisioningUpdates \
  install

# install 산출물 우선, 없으면 Debug-iphoneos
APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*InstallationBuildProductsLocation/Applications/BikeComputer.app' -not -path '*Index*' 2>/dev/null | head -1)
if [[ -z "$APP" ]]; then
  APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphoneos/BikeComputer.app' -not -path '*Index*' 2>/dev/null | head -1)
fi
WATCH_EMBED="${APP}/PlugIns/BikeComputerWatch.app"
WATCH_STANDALONE="$("${ROOT}/scripts/resolve_watch_app.sh" 2>/dev/null || true)"

if [[ -z "$APP" || ! -d "$WATCH_EMBED" ]]; then
  echo "❌ BikeComputer.app 또는 PlugIns/BikeComputerWatch.app 없음"
  exit 1
fi
if [[ -z "$WATCH_STANDALONE" || ! -d "$WATCH_STANDALONE" ]]; then
  echo "❌ Debug-watchos/BikeComputerWatch.app 없음"
  exit 1
fi

echo "   ✓ iPhone 번들: $APP"
echo "   ✓ Watch embed: $WATCH_EMBED"
echo "   ✓ Watch 빌드:  $WATCH_STANDALONE"
"${ROOT}/scripts/ensure_watch_icon_plist.sh" "$WATCH_EMBED/Info.plist"
"${ROOT}/scripts/ensure_watch_icon_plist.sh" "$WATCH_STANDALONE/Info.plist"

WATCH_OK=0
echo "==> 3. Watch companion 설치"
echo "   (PlugIns 사본은 Watch 직접 설치 불가 — watchOS 빌드 사용)"
if "${ROOT}/scripts/install_watch.sh"; then
  WATCH_OK=1
fi

echo ""
echo "==> 4. 확인"
echo ""
echo "  iPhone 앱 → Devices 탭:"
echo "    · 페어링: 됨"
echo "    · Watch 앱: 설치됨"
echo "    · WatchConnectivity: 활성"
echo ""

if [[ "$WATCH_OK" -eq 0 ]]; then
  cat <<EOF
  ⚠️  Watch 직접 설치는 터널 오류로 실패했지만 iPhone 설치는 완료됐을 수 있습니다.
      아래 수동 설치를 먼저 시도하세요:

  ★ iPhone Watch 앱 → 일반 → BikeComputer → "Apple Watch에 설치" ON
    (1~2분 후 Watch 홈에서 BikeComputer 확인)

  터널 복구 후 Watch만 다시 설치:
    ./scripts/install_watch.sh \\
      $WATCH_STANDALONE

EOF
fi

cat <<'EOF'
  그래도 안 되면:
    ① iPhone USB 연결, Xcode Devices → iPhone "Connect via network" OFF
    ② Watch 설정 → 개발자 모드 ON (재부팅)
    ③ iPhone·Watch 에서 BikeComputer 삭제 후 install_device.sh 재실행

  ⚠️ BikeComputer 스킴만 사용 — iPhone 재설치 전 Watch 단독 설치 금지

EOF
