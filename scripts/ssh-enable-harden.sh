#!/usr/bin/env bash
# ssh-enable-harden.sh — enable Remote Login (SSH) and sanity-check key auth.
#
# INTERACTIVE ON PURPOSE. This needs `sudo systemsetup`, which is NOT in the
# passwordless grant, so it will prompt for your password. It does NOT edit
# sshd_config automatically (that risks locking you out); instead it enables
# SSH, checks you have a key installed, and PRINTS the optional hardening steps.
#
#   scripts/ssh-enable-harden.sh          # enable + check (prompts for sudo)
#   scripts/ssh-enable-harden.sh --check  # read-only: report, change nothing
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SELF_DIR/../lib/common.sh"

CHECK_ONLY=0; [ "${1:-}" = "--check" ] && CHECK_ONLY=1

log "SSH / Remote Login setup"

# 1. report current state
if launchctl print system/com.openssh.sshd >/dev/null 2>&1; then
  ok "Remote Login appears ON (sshd registered)"
  ssh_on=1
else
  warn "Remote Login appears OFF"
  ssh_on=0
fi

# 2. key check
akeys="$HOME/.ssh/authorized_keys"
if [ -s "$akeys" ]; then
  ok "authorized_keys present ($(grep -c . "$akeys") line(s))"
else
  warn "no ~/.ssh/authorized_keys — add your client's public key BEFORE disabling password auth, or you can lock yourself out."
fi

if [ "$CHECK_ONLY" = "1" ]; then
  dim "--check: no changes made."
  exit 0
fi

# 3. enable if needed (interactive sudo)
if [ "$ssh_on" = "0" ]; then
  log "enabling Remote Login (will prompt for sudo password)"
  sudo systemsetup -setremotelogin on
  ok "Remote Login enabled"
else
  dim "Remote Login already on; nothing to enable."
fi

cat <<'EOF'

Optional hardening (do manually, carefully, with a key already working):
  1. Confirm you can SSH in with your KEY from another device first.
  2. Then disable password auth:
       sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)
       # set:  PasswordAuthentication no
       #       KbdInteractiveAuthentication no
     (edit /etc/ssh/sshd_config.d/*.conf or the main file)
  3. Reload sshd. Keep your current session open until you've verified a NEW
     key-only login works, so a mistake can't lock you out.
  Behind Tailscale this is lower-stakes (the box isn't on the public internet),
  but key-only is still the right default.
EOF
