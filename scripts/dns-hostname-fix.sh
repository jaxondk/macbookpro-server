#!/usr/bin/env bash
# dns-hostname-fix.sh — keep MagicDNS hostnames AND the Claude Code TLS fix.
#
# Background: ../tailscale-claude-code-fix.md documents that --accept-dns=true
# breaks TLS for Claude Code et al. on this machine. The fix below turns global
# Tailscale DNS off (restoring TLS) but adds a per-domain resolver so *.ts.net
# names still resolve via Tailscale's 100.100.100.100. Net result: stable
# hostnames to reach this box, no broken TLS.
#
# NETWORK-SENSITIVE + INTERACTIVE. `tee /etc/resolver` needs sudo (NOT in the
# passwordless grant). Changing DNS can disrupt connectivity, so this defaults
# to a dry plan; pass --apply to actually change things, ideally while you have
# a second device on the tailnet to verify you didn't lock yourself out.
#
#   scripts/dns-hostname-fix.sh           # show the plan + current state
#   scripts/dns-hostname-fix.sh --apply   # apply (prompts for sudo)
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SELF_DIR/../lib/common.sh"

TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
[ -x "$TS" ] || die "Tailscale app not found at $TS"

log "current Tailscale DNS state"
"$TS" dns status 2>&1 | sed 's/^/  /' || true
echo "resolver file /etc/resolver/ts.net:"
[ -f /etc/resolver/ts.net ] && sed 's/^/  /' /etc/resolver/ts.net || echo "  (absent)"
echo

if [ "$APPLY" = "0" ]; then
  cat <<EOF
PLAN (re-run with --apply to execute; needs sudo):
  1. $TS set --accept-dns=false          # restores TLS; drops global MagicDNS
  2. sudo mkdir -p /etc/resolver
  3. echo "nameserver 100.100.100.100" | sudo tee /etc/resolver/ts.net
                                         # *.ts.net names resolve again

VERIFY after applying:
  - $TS dns status            # should show Tailscale DNS disabled
  - scutil --dns | grep -A2 ts.net      # resolver for ts.net present
  - ping -c1 <thishost>.<tailnet>.ts.net   (from another tailnet device)
  - curl -sS -o /dev/null -w '%{http_code}\\n' https://api.anthropic.com/  # not reset
EOF
  exit 0
fi

warn "applying DNS changes — keep a second tailnet device handy to verify."
run "$TS" set --accept-dns=false
run sudo mkdir -p /etc/resolver
if is_dry_run; then
  dim "[dry-run] echo 'nameserver 100.100.100.100' | sudo tee /etc/resolver/ts.net"
else
  echo "nameserver 100.100.100.100" | sudo tee /etc/resolver/ts.net >/dev/null
fi
ok "applied. Verify with the VERIFY steps above."
