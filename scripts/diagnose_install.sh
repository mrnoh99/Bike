#!/usr/bin/env bash
# Watch 설치 문제 진단
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DEVICECTL="${DEVELOPER_DIR}/usr/bin/devicectl"

echo "==> 기기"
xcrun xctrace list devices 2>/dev/null | grep -E 'iPhone|Watch' | grep -v Simulator || true
echo ""
if [[ -x "$DEVICECTL" ]]; then
  "$DEVICECTL" list devices 2>/dev/null | grep -E 'iPhone|Watch' | grep -v unavailable || true
fi

echo ""
echo "==> 최근 빌드 산출물"
APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphoneos/BikeComputer.app' -not -path '*Index*' 2>/dev/null | head -1)
EMBED="${APP}/PlugIns/BikeComputerWatch.app"
STANDALONE=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-watchos/BikeComputerWatch.app' -not -path '*Index*' 2>/dev/null | head -1)

if [[ -z "$APP" ]]; then
  echo "❌ BikeComputer.app 없음 — ./scripts/check_watch.sh 실행"
  exit 1
fi
echo "✓ iPhone: $APP"
[[ -d "$EMBED" ]] && echo "✓ PlugIns: $EMBED" || echo "❌ PlugIns 없음"
[[ -d "$STANDALONE" ]] && echo "✓ watchOS: $STANDALONE" || echo "❌ watchOS 빌드 없음"

if [[ -d "$EMBED" ]]; then
  echo ""
  echo "==> PlugIns Watch 서명 (Watch 직접 설치 불가 — 정상)"
  codesign --verify --deep --strict "$EMBED" 2>&1 && echo "   embed 서명 OK" || echo "   embed 서명 문제"
fi
if [[ -d "$STANDALONE" ]]; then
  echo ""
  echo "==> watchOS Watch 서명 (Watch 설치용)"
  codesign --verify --deep --strict "$STANDALONE" 2>&1 && echo "   watchOS 서명 OK" || echo "   watchOS 서명 문제"
  if /usr/libexec/PlistBuddy -c "Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName" "$STANDALONE/Info.plist" >/dev/null 2>&1; then
    echo "   CFBundleIconName OK"
  else
    echo "   ❌ CFBundleIconName 없음"
  fi
fi

echo ""
echo "설치:"
echo "  ./scripts/install_device.sh <iPhone-UDID>"
echo "  (Watch 터널 실패 시) iPhone Watch 앱 → 일반 → BikeComputer → 설치 ON"
if [[ -n "$STANDALONE" ]]; then
  echo "  (터널 복구 후) ./scripts/install_watch.sh $STANDALONE"
fi
