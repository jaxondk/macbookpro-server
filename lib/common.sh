#!/usr/bin/env bash
# Shared helpers for macsimize scripts. Source, don't execute.
# shellcheck shell=bash

# Resolve the repo root from this file's location, regardless of CWD.
_common_src="${BASH_SOURCE[0]}"
LIB_DIR="$(cd "$(dirname "$_common_src")" && pwd)"
REPO_ROOT="$(cd "$LIB_DIR/.." && pwd)"
STATE_DIR="$REPO_ROOT/state"

# DRY_RUN=1 makes run() print commands instead of executing them.
: "${DRY_RUN:=0}"

# --- logging -----------------------------------------------------------------
_c_reset=$'\033[0m'; _c_blue=$'\033[34m'; _c_yellow=$'\033[33m'
_c_red=$'\033[31m'; _c_green=$'\033[32m'; _c_dim=$'\033[2m'
# Disable color if not a tty.
if [ ! -t 1 ]; then _c_reset=; _c_blue=; _c_yellow=; _c_red=; _c_green=; _c_dim=; fi

log()  { printf '%s==>%s %s\n' "$_c_blue" "$_c_reset" "$*"; }
ok()   { printf '%s ok %s %s\n' "$_c_green" "$_c_reset" "$*"; }
warn() { printf '%swarn%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
err()  { printf '%serr %s %s\n' "$_c_red" "$_c_reset" "$*" >&2; }
dim()  { printf '%s%s%s\n' "$_c_dim" "$*" "$_c_reset"; }
die()  { err "$*"; exit 1; }

# run CMD...  — echoes the command; executes unless DRY_RUN=1.
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s[dry-run]%s %s\n' "$_c_dim" "$_c_reset" "$*"
    return 0
  fi
  printf '%s+%s %s\n' "$_c_dim" "$_c_reset" "$*"
  "$@"
}

is_dry_run() { [ "$DRY_RUN" = "1" ]; }

# ask_yn PROMPT [default:y|n] — prompt for a yes/no answer; returns 0 for yes.
# Non-interactive (no tty) or ASSUME_YES=1 returns the default without asking,
# so setup still runs in pipes/CI and honors a --yes flag.
ask_yn() {
  local prompt="$1" def="${2:-y}" ans hint
  if [ "${ASSUME_YES:-0}" = "1" ] || [ ! -t 0 ]; then
    [ "$def" = "y" ]; return
  fi
  hint="[Y/n]"; [ "$def" = "n" ] && hint="[y/N]"
  printf '%s%s?%s %s ' "$_c_blue" "$prompt" "$_c_reset" "$hint" >&2
  read -r ans || ans=""
  ans="${ans:-$def}"
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

# Hardware profile detection: "laptop" (has a battery) or "desktop" (mini etc).
host_profile() {
  if pmset -g batt 2>/dev/null | grep -q "InternalBattery"; then
    echo laptop
  else
    echo desktop
  fi
}

ensure_state_dir() { mkdir -p "$STATE_DIR"; }

# Desired mode: which mode to re-assert on boot. Written by `macsimize
# server|laptop`, read by the boot re-assert agent. Absent => do nothing on boot.
DESIRED_MODE_FILE="$STATE_DIR/desired-mode"
set_desired_mode() {
  is_dry_run && { dim "[dry-run] would record desired mode: $1"; return 0; }
  ensure_state_dir; printf '%s\n' "$1" > "$DESIRED_MODE_FILE"
}
get_desired_mode() { [ -f "$DESIRED_MODE_FILE" ] || return 0; tr -d '[:space:]' < "$DESIRED_MODE_FILE"; }
