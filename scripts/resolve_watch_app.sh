#!/usr/bin/env bash
# watchOS 빌드 산출물 경로를 실제 .app 디렉터리로 해석 (PlugIns 제외)
set -euo pipefail

if [[ $# -gt 0 && -n "${1:-}" ]]; then
  CANDIDATE="$1"
  REAL=$(cd "$(dirname "$CANDIDATE")" 2>/dev/null && pwd -P)/$(basename "$CANDIDATE")
  [[ -d "$REAL" ]] && echo "$REAL" && exit 0
  echo "❌ Watch 앱 없음: $1" >&2
  exit 1
fi

DD=~/Library/Developer/Xcode/DerivedData
CANDIDATE=$(find "$DD"/BikeComputer-* \
  \( -path '*/Debug-watchos/BikeComputerWatch.app' \
     -o -path '*/UninstalledProducts/watchos/BikeComputerWatch.app' \) \
  -not -path '*PlugIns*' -not -path '*Index*' 2>/dev/null \
  | xargs ls -td 2>/dev/null | head -1)

if [[ -z "${CANDIDATE:-}" ]]; then
  echo "❌ Debug-watchos/BikeComputerWatch.app 없음 — 먼저 빌드하세요:" >&2
  echo "   ./scripts/install_device.sh <iPhone-UDID>" >&2
  exit 1
fi

REAL=$(cd "$(dirname "$CANDIDATE")" && pwd -P)/$(basename "$CANDIDATE")
if [[ ! -d "$REAL" ]]; then
  echo "❌ Watch 앱 경로 해석 실패: $CANDIDATE" >&2
  exit 1
fi
echo "$REAL"
