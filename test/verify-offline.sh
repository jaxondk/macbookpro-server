#!/usr/bin/env bash
# verify-offline.sh — everything we can check WITHOUT applying changes or sudo.
# Safe to run anytime. Exits non-zero if any check fails.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
pass() { printf '  PASS  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }
hdr()  { printf '\n== %s ==\n' "$*"; }

scripts=(bin/macsimize scripts/bootstrap scripts/ssh-enable-harden.sh \
         scripts/dns-hostname-fix.sh scripts/boot-reassert.sh test/verify-offline.sh)
libs=(lib/common.sh lib/power.sh lib/caffeinate.sh lib/reassert.sh \
      lib/tailscale.sh lib/mosh.sh lib/prefs.sh lib/setup.sh)

hdr "bash syntax (-n)"
for f in "${scripts[@]}" "${libs[@]}"; do
  if bash -n "$f" 2>/dev/null; then pass "$f"; else bad "$f"; fi
done

hdr "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  for f in "${scripts[@]}" "${libs[@]}"; do
    if shellcheck -x "$f" >/tmp/sc.$$ 2>&1; then pass "$f"; else bad "$f"; cat /tmp/sc.$$ | sed 's/^/        /'; fi
  done
  rm -f /tmp/sc.$$
else
  echo "  (shellcheck not installed — skipped)"
fi

hdr "plist lint"
if plutil -lint launchd/*.plist >/dev/null 2>&1; then pass "launchd/*.plist"; else bad "plist invalid"; fi

hdr "macsimize status (read-only)"
if bin/macsimize status >/dev/null 2>&1; then pass "status runs"; else bad "status errored"; fi

hdr "dry-run setup + server + laptop (no changes)"
if bin/macsimize server --dry-run >/dev/null 2>&1; then pass "server --dry-run"; else bad "server --dry-run"; fi
if bin/macsimize laptop --dry-run >/dev/null 2>&1; then pass "laptop --dry-run"; else bad "laptop --dry-run"; fi
if bin/macsimize setup --dry-run >/dev/null 2>&1; then pass "setup --dry-run"; else bad "setup --dry-run"; fi

hdr "power snapshot round-trip (read-only, temp state dir)"
# Exercise snapshot_power for real against a throwaway STATE_DIR; it only READS
# pmset, never writes settings, so this is safe.
tmp="$(mktemp -d)"
if (
  export DRY_RUN=0
  source lib/common.sh
  # shellcheck disable=SC2034  # read by lib/power.sh after this override
  STATE_DIR="$tmp"
  source lib/power.sh
  snapshot_power >/dev/null 2>&1
  keys=(sleep disksleep powernap womp autorestart disablesleep)
  for k in "${keys[@]}"; do grep -q "^$k=" "$tmp/pmset-restore.env" || exit 3; done
); then pass "snapshot wrote all keys"; else bad "snapshot missing keys"; fi
rm -rf "$tmp"

hdr "result"
if [ "$fail" = "0" ]; then echo "  ALL CHECKS PASSED"; else echo "  SOME CHECKS FAILED"; fi
exit "$fail"
