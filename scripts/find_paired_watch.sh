#!/usr/bin/env bash
# 페어링된 Apple Watch ID 조회
# 사용: find_paired_watch.sh [core|udid]  (기본: core = devicectl ID)
set -euo pipefail

MODE="${1:-core}"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DEVICECTL="${DEVELOPER_DIR}/usr/bin/devicectl"

core_id() {
  [[ -x "$DEVICECTL" ]] || return 1
  "$DEVICECTL" list devices 2>/dev/null | awk '
    /Watch/ && /paired/ && !/unavailable/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-/) { print $i; exit }
      }
    }
  '
}

udid_id() {
  xcrun xctrace list devices 2>/dev/null | grep -E 'Watch|Apple Watch' | grep -v Simulator \
    | sed -n 's/.*(\([0-9A-Fa-f-]\{8,\}\)).*/\1/p' | head -1
}

case "$MODE" in
  core) core_id || udid_id ;;
  udid) udid_id ;;
  *) core_id || udid_id ;;
esac
