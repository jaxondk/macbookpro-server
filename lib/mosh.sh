#!/usr/bin/env bash
# mosh: install the server side so mobile clients can use the mosh transport.
# Sourced by scripts/setup and bin/servermode (which source common.sh first).
#
# WHY THIS LIVES HERE: mosh is a *reachability* concern — mobile clients like
# Moshi (getmoshi.app) or Blink use mosh to survive flaky links and IP changes
# when you connect from a phone. Only the server side (mosh-server) is needed on
# this box; the client lives on your phone. mosh traffic is carried over the
# tailnet, so there are NO UDP ports to forward or firewall holes to open.
# shellcheck shell=bash

mosh_is_installed() { command -v mosh-server >/dev/null 2>&1; }

mosh_install() {
  if mosh_is_installed; then ok "mosh-server present ($(command -v mosh-server))"; return 0; fi
  if command -v brew >/dev/null 2>&1; then
    log "installing mosh via Homebrew"
    run brew install mosh
    mosh_is_installed
    return
  fi
  warn "mosh not installed and Homebrew not found."
  dim "  Install with: brew install mosh   (or see https://mosh.org/#getting)"
  return 1
}

# One read-only line for `servermode status` / setup summaries.
mosh_status() {
  if mosh_is_installed; then
    echo "  mosh-server: present (mobile clients can use the mosh transport)"
  else
    echo "  mosh-server: not installed (run scripts/setup, or: brew install mosh)"
  fi
}
