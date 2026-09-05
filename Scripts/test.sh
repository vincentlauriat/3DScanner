#!/usr/bin/env bash
# Lance les tests unitaires sur les deux plateformes sans signature et résume.
# Usage : Scripts/test.sh [ios|mac|all]   (défaut : all)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
WHAT="${1:-all}"
SIM="${SIM:-$(xcrun simctl list devices available | grep -oE 'iPhone 1[5-9] Pro( Max)?' | sort -u | tail -1)}"
status=0
run() { # $1 label, reste = arguments xcodebuild
  local label="$1"; shift
  echo "### $label"
  xcodebuild "$@" CODE_SIGNING_ALLOWED=NO test 2>&1 \
    | grep -E "error:|error \(|failed|Executed [0-9]+ tests|\*\* TEST" | grep -v "linkd" | sort -u
  local rc=${PIPESTATUS[0]}
  [ "$rc" -ne 0 ] && { echo "✗ $label a échoué (xcodebuild rc=$rc)"; status=1; }
}
[ "$WHAT" = ios ] || [ "$WHAT" = all ] && run "iOS ($SIM)" -scheme RoomScanner -destination "platform=iOS Simulator,name=$SIM"
[ "$WHAT" = mac ] || [ "$WHAT" = all ] && run "macOS" -scheme RoomScannerMac -destination 'platform=macOS'
exit $status
