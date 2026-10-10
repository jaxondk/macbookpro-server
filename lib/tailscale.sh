#!/usr/bin/env bash
# Tailscale: install (standalone, headless-friendly) + configure for server use.
# Sourced by bin/macsimize (which source common.sh first).
#
# WHY THIS LIVES HERE: Tailscale is the *reachability* layer — it's what makes
# the box reachable as a server. So this repo owns its server-side configuration
# (and will install it if missing to stay turnkey). Your dotfiles may also list
# tailscale as a package; if so, the install step just detects it and skips.
#
# We standardize on the STANDALONE variant (bundle id io.tailscale.ipn.macsys,
# `brew install --cask tailscale`), NOT the Mac App Store build: the standalone
# one runs a real system daemon and comes up at boot, which is what a headless
# server needs. The App Store build is sandboxed and only runs with a GUI login.
# shellcheck shell=bash

TS_APP="/Applications/Tailscale.app/Contents/MacOS/Tailscale"

# Resolve the tailscale CLI, preferring the brew/standalone symlinks.
ts_bin() {
  local b
  for b in /usr/local/bin/tailscale /opt/homebrew/bin/tailscale "$TS_APP"; do
    [ -x "$b" ] && { echo "$b"; return 0; }
  done
  return 1
}

tailscale_is_installed() { ts_bin >/dev/null 2>&1; }

# Backend state: "Running", "Stopped", "NeedsLogin", "NoState", or "" if unknown.
tailscale_state() {
  local b; b="$(ts_bin)" || { echo ""; return; }
  "$b" status --json 2>/dev/null \
    | grep -o '"BackendState"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

tailscale_is_up() { [ "$(tailscale_state)" = "Running" ]; }

# Install the standalone app if absent. Returns non-zero if it couldn't (no brew
# and not present) so the caller can record a manual step. The system-extension
# approval + login are inherently interactive and are surfaced, not faked.
tailscale_install() {
  if tailscale_is_installed; then ok "tailscale present ($(ts_bin))"; return 0; fi
  if command -v brew >/dev/null 2>&1; then
    log "installing Tailscale (standalone) via Homebrew"
    run brew install --cask tailscale
    tailscale_is_installed
    return
  fi
  warn "Tailscale not installed and Homebrew not found."
  dim "  Install the standalone app from https://tailscale.com/download/macos then re-run."
  return 1
}

# Apply the server-use settings on an already-authenticated node:
#   --ssh             advertise Tailscale SSH (identity rides the tailnet)
#   --accept-dns=false the Claude Code TLS/ECONNRESET fix (see docs/PLAN.md)
tailscale_configure() {
  local b; b="$(ts_bin)" || { warn "tailscale CLI not found; skipping config"; return 1; }
  log "configuring Tailscale for server use (--ssh, --accept-dns=false)"
  run "$b" set --ssh=true --accept-dns=false
}

# One read-only line for `macsimize status` / setup summaries.
tailscale_status() {
  local b; if ! b="$(ts_bin)"; then echo "  tailscale: not installed"; return; fi
  local state ip name
  state="$(tailscale_state)"; [ -z "$state" ] && state="unknown"
  ip="$("$b" ip -4 2>/dev/null | head -1)"
  name="$(scutil --get LocalHostName 2>/dev/null || true)"
  echo "  tailscale: $state  (host '${name:-?}', ip ${ip:-unknown})"
}
