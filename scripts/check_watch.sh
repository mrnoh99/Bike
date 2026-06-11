#!/usr/bin/env bash
# Watch 앱이 빌드·임베드 되는지 확인
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
XCODEBUILD="${DEVELOPER_DIR}/usr/bin/xcodebuild"

echo "==> xcodegen"
xcodegen generate
./scripts/prune_watch_scheme.sh

echo "==> 타깃 확인"
"$XCODEBUILD" -project BikeComputer.xcodeproj -list | grep -E 'Targets:|BikeComputer'

echo "==> 빌드 (iPhone + Watch)"
"$XCODEBUILD" \
  -project BikeComputer.xcodeproj \
  -scheme BikeComputer \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO

APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphoneos/BikeComputer.app' -not -path '*Index*' 2>/dev/null | head -1)
WATCH="$APP/PlugIns/BikeComputerWatch.app"

echo ""
echo "==> 결과"
if [[ -z "$APP" ]]; then
  echo "❌ BikeComputer.app 없음"
  exit 1
fi
echo "✓ iPhone 앱: $APP"

if [[ ! -d "$WATCH" ]]; then
  echo "❌ Watch 앱 없음: $WATCH"
  echo "   → Product → Scheme → Edit Scheme → Build 에 BikeComputerWatch 체크"
  exit 1
fi
echo "✓ Watch 앱: $WATCH"

if [[ ! -f "$WATCH/Assets.car" ]]; then
  echo "❌ Watch 아이콘(Assets.car) 없음 — 실기기 설치 실패 원인"
  exit 1
fi
echo "✓ Watch 아이콘: Assets.car"

plutil -p "$WATCH/Info.plist" | grep -E 'CFBundleIdentifier|CFBundleDisplayName|WKApplication|WKCompanion' || true

if ! plutil -extract WKApplication raw "$WATCH/Info.plist" 2>/dev/null | grep -q true; then
  echo "❌ WKApplication=true 없음 — 실기기 설치 실패 원인"
  exit 1
fi
echo "✓ WKApplication: true"

"$ROOT/scripts/ensure_watch_icon_plist.sh" "$WATCH/Info.plist"
ICON_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName" "$WATCH/Info.plist")
echo "✓ CFBundleIconName: $ICON_NAME"

echo ""
echo "✅ 빌드 OK — Watch 앱은 iPhone 앱 안에 포함되어 있습니다."
echo ""
echo "⚠️  check_watch.sh 는 기기에 설치하지 않습니다."
echo "실기기 설치:"
echo "  1) Xcode: BikeComputer 스킴 → iPhone → Team 서명 → ⌘R (Watch 스킴 직접 Run 금지)"
echo "  2) 또는: ./scripts/install_device.sh <iPhone-UDID>  (iPhone+Watch 동시 설치)"
echo "  3) 문제 시: ./scripts/diagnose_install.sh"
echo "  4) iPhone Watch 앱 → 일반 → BikeComputer → 설치 ON"
echo "  5) Watch: 설정 → 개발자 모드 ON (최초 1회)"
