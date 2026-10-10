#!/usr/bin/env bash
# Power-management profile: snapshot, apply server settings, restore.
# Sourced by bin/macsimize (which sources common.sh first).
# shellcheck shell=bash

POWER_SNAPSHOT_RAW="$STATE_DIR/pmset-backup.txt"   # human-readable full dump
POWER_RESTORE="$STATE_DIR/pmset-restore.env"       # parsed originals we restore

# Keys we touch on AC power. We only ever use `pmset -c` so battery behavior
# (and thus "sleeps normally when unplugged / in a bag") is left untouched.
POWER_KEYS=(sleep disksleep powernap womp autorestart disablesleep)

# Server profile values for those keys, in the same order.
POWER_SERVER=(0 0 0 1 1 1)

# Read one key's current value. Most keys come from the AC Power block of
# `pmset -g custom`, but two are reported elsewhere:
#   disablesleep -> shown as "SleepDisabled" in `pmset -g` (global, not per-source)
#   autorestart  -> not reported on laptops; best-effort from `pmset -g`
# Prints the value, or empty string if the key is absent/unreadable.
_read_ac_key() {
  local key="$1"
  case "$key" in
    disablesleep)
      pmset -g 2>/dev/null | awk '$1=="SleepDisabled"{print $2; f=1} END{if(!f)print ""}'
      return ;;
    autorestart)
      pmset -g 2>/dev/null | awk 'tolower($1)=="autorestart"{print $2; f=1} END{if(!f)print ""}'
      return ;;
  esac
  pmset -g custom \
    | awk '/^[A-Za-z].*Power:/{inac=($0 ~ /^AC Power:/)?1:0; next} inac{print}' \
    | awk -v k="$key" '$1==k{print $2; f=1} END{if(!f)print ""}'
}

# Capture the pre-server baseline exactly once. If POWER_RESTORE already exists
# we do NOT overwrite it — otherwise flipping to server twice would record the
# server values as the "original" and laptop-mode could never restore.
snapshot_power() {
  ensure_state_dir
  if [ -f "$POWER_RESTORE" ]; then
    dim "baseline already captured at $POWER_RESTORE (keeping it)"
    return 0
  fi
  log "capturing current power baseline -> $POWER_RESTORE"
  if is_dry_run; then
    dim "[dry-run] would write baseline for: ${POWER_KEYS[*]}"
    return 0
  fi
  pmset -g custom > "$POWER_SNAPSHOT_RAW" 2>/dev/null || true
  : > "$POWER_RESTORE"
  local k v
  for k in "${POWER_KEYS[@]}"; do
    v="$(_read_ac_key "$k")"
    [ -z "$v" ] && v=0   # absent means effectively off for the keys we set
    printf '%s=%s\n' "$k" "$v" >> "$POWER_RESTORE"
  done
  ok "baseline saved"
  dim "$(tr '\n' ' ' < "$POWER_RESTORE")"
}

apply_server_power() {
  log "applying server power profile (AC only)"
  local i args=()
  for i in "${!POWER_KEYS[@]}"; do
    args+=("${POWER_KEYS[$i]}" "${POWER_SERVER[$i]}")
  done
  run sudo pmset -c "${args[@]}"
  ok "server power profile applied: ${args[*]}"
}

restore_power() {
  if [ ! -f "$POWER_RESTORE" ]; then
    warn "no baseline at $POWER_RESTORE — cannot restore exact originals."
    warn "leaving power settings as-is. Review with: pmset -g custom"
    return 1
  fi
  log "restoring pre-server power baseline (AC)"
  local args=() k v
  while IFS='=' read -r k v; do
    [ -z "$k" ] && continue
    args+=("$k" "$v")
  done < "$POWER_RESTORE"
  run sudo pmset -c "${args[@]}"
  ok "power baseline restored: ${args[*]}"
}

# Print current AC values for the keys we care about (no sudo, read-only).
power_status() {
  local k v
  for k in "${POWER_KEYS[@]}"; do
    v="$(_read_ac_key "$k")"; [ -z "$v" ] && v="(unset)"
    # autorestart isn't reported on laptops (battery is the UPS) — label it so
    # "(unset)" doesn't look like a failure. It matters on the Mac mini.
    if [ "$k" = "autorestart" ] && [ "$v" = "(unset)" ] && [ "$(host_profile)" = "laptop" ]; then
      v="(n/a on laptop — battery is the UPS; matters on the mini)"
    fi
    printf '  %-12s %s\n' "$k" "$v"
  done
}
