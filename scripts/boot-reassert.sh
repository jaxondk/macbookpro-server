#!/usr/bin/env bash
# boot-reassert.sh — run at login by the boot-reassert LaunchAgent.
# Re-applies whichever mode was last set (state/desired-mode). No-op if unset.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SELF_DIR/../lib/common.sh"

mode="$(get_desired_mode)"
ts="$(date '+%Y-%m-%d %H:%M:%S')"
case "$mode" in
  server|laptop)
    echo "[$ts] boot-reassert: re-asserting '$mode' mode"
    exec "$SELF_DIR/../bin/macsimize" "$mode"
    ;;
  "")
    echo "[$ts] boot-reassert: no desired mode recorded — doing nothing"
    ;;
  *)
    echo "[$ts] boot-reassert: unrecognized desired mode '$mode' — doing nothing" >&2
    exit 0
    ;;
esac
