#!/usr/bin/env bash
# BikeComputerWatch 스킴 제거 + Xcode 자동 스킴 생성 비활성화
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="${ROOT}/BikeComputer.xcodeproj"
SCHEMES_DIR="${PROJ}/xcshareddata/xcschemes"
WORKSPACE_DIR="${PROJ}/project.xcworkspace/xcshareddata"

mkdir -p "$WORKSPACE_DIR" "$SCHEMES_DIR"
cp "${ROOT}/Xcode/WorkspaceSettings.xcsettings" "${WORKSPACE_DIR}/WorkspaceSettings.xcsettings"

rm -f "${SCHEMES_DIR}/BikeComputerWatch.xcscheme"
find "${PROJ}/xcuserdata" -name 'BikeComputerWatch.xcscheme' -delete 2>/dev/null || true

for plist in "${PROJ}"/xcuserdata/*/xcschemes/xcschememanagement.plist; do
  [[ -f "$plist" ]] || continue
  /usr/libexec/PlistBuddy -c "Delete :SchemeUserState:BikeComputerWatch.xcscheme_^#shared#^_" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :SchemeUserState:BikeComputerWatch.xcscheme" "$plist" 2>/dev/null || true
done

if [[ -f "${SCHEMES_DIR}/BikeComputerWatch.xcscheme" ]]; then
  echo "error: BikeComputerWatch.xcscheme still present" >&2
  exit 1
fi
