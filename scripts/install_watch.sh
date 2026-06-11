#!/usr/bin/env bash
# Watch companion 설치 (재시도 + 터널 오류 대응)
# 인자: (선택) watchOS 빌드 산출물 경로 — 없으면 최신 빌드 자동 탐색
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DEVICECTL="${DEVELOPER_DIR}/usr/bin/devicectl"

if [[ ! -x "$DEVICECTL" ]]; then
  echo "❌ devicectl 없음" >&2
  exit 1
fi

WATCH_SRC="$("${ROOT}/scripts/resolve_watch_app.sh" "${1:-}")"
STAGE=$(mktemp -d /tmp/BikeComputerWatch-install.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT

echo "==> Watch 앱 준비"
echo "   원본: $WATCH_SRC"
ditto "$WATCH_SRC" "$STAGE/BikeComputerWatch.app"
WATCH_APP="$STAGE/BikeComputerWatch.app"
"${ROOT}/scripts/ensure_watch_icon_plist.sh" "$WATCH_APP/Info.plist"

CORE_ID="$("${ROOT}/scripts/find_paired_watch.sh" core 2>/dev/null || true)"
XCTrace_ID="$("${ROOT}/scripts/find_paired_watch.sh" udid 2>/dev/null || true)"

ids=()
[[ -n "$CORE_ID" ]] && ids+=("$CORE_ID")
[[ -n "$XCTrace_ID" && "$XCTrace_ID" != "$CORE_ID" ]] && ids+=("$XCTrace_ID")

if [[ ${#ids[@]} -eq 0 ]]; then
  echo "❌ 페어링된 Watch 없음" >&2
  exit 1
fi

echo "==> 터널 확인 (Watch 잠금 해제·iPhone 옆에 두기)"
for wid in "${ids[@]}"; do
  if "$DEVICECTL" device info --device "$wid" >/dev/null 2>&1; then
    echo "   ✓ Watch 응답: $wid"
  else
    echo "   ⚠️ Watch 응답 없음: $wid"
  fi
done

install_once() {
  local id="$1"
  local attempt="$2"
  echo "   시도 ${attempt}: $id"
  if "$DEVICECTL" device install app --device "$id" "$WATCH_APP" 2>&1; then
    if "$DEVICECTL" device info apps --device "$id" 2>/dev/null | grep -q 'com.jaisungnoh.bikecomputer.watchkitapp'; then
      return 0
    fi
    echo "   ⚠️ 설치 명령 성공했으나 앱 목록에 없음"
  fi
  return 1
}

for round in 1 2 3 4 5; do
  echo "==> Watch 설치 (${round}/5)"
  for wid in "${ids[@]}"; do
    if install_once "$wid" "$round"; then
      echo "   ✓ Watch 설치 확인됨 (com.jaisungnoh.bikecomputer.watchkitapp)"
      exit 0
    fi
  done
  [[ "$round" -lt 5 ]] && sleep 12
done

cat <<'EOF' >&2

❌ Watch 설치 실패

  1) iPhone USB 연결 (Wi‑Fi만 X)
  2) Xcode → Devices → iPhone → "Connect via network" OFF
  3) Watch 설정 → 개발자 모드 ON, 잠금 해제, iPhone 옆에 두기
  4) 재시도: ./scripts/install_watch.sh
  5) 또는 Xcode: BikeComputer 스킴 → iPhone12mini → ⌘R

EOF
exit 1
