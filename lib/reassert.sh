#!/usr/bin/env bash
# Manage the boot-reassert LaunchAgent (user-level, NO sudo).
# Installed once; stays loaded in BOTH modes so it can restore laptop OR server
# on boot per state/desired-mode. Sourced by bin/macsimize.
# shellcheck shell=bash

REASSERT_LABEL="com.macsimize.boot-reassert"
REASSERT_LABEL_OLD="com.macbookpro-server.boot-reassert"   # pre-rename; migrated away on install
REASSERT_SRC="$REPO_ROOT/launchd/$REASSERT_LABEL.plist"
REASSERT_DEST="$HOME/Library/LaunchAgents/$REASSERT_LABEL.plist"

reassert_is_loaded() { launchctl print "gui/$(id -u)/$REASSERT_LABEL" >/dev/null 2>&1; }

reassert_install() {
  log "installing boot-reassert LaunchAgent (user-level, no sudo)"
  if is_dry_run; then
    dim "[dry-run] render $REASSERT_SRC (sub __MACSIMIZE_REPO__=$REPO_ROOT) -> $REASSERT_DEST"
    dim "[dry-run] launchctl bootstrap gui/\$(id -u) $REASSERT_DEST"
    return 0
  fi
  mkdir -p "$HOME/Library/LaunchAgents"
  # Migrate away from the pre-rename label if it's still around.
  launchctl bootout "gui/$(id -u)/$REASSERT_LABEL_OLD" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/LaunchAgents/$REASSERT_LABEL_OLD.plist"
  sed "s#__MACSIMIZE_REPO__#$REPO_ROOT#g" "$REASSERT_SRC" > "$REASSERT_DEST"
  launchctl bootout "gui/$(id -u)/$REASSERT_LABEL" >/dev/null 2>&1 || true
  if launchctl bootstrap "gui/$(id -u)" "$REASSERT_DEST" 2>/dev/null; then
    ok "boot-reassert agent installed + loaded"
  elif launchctl load "$REASSERT_DEST" >/dev/null 2>&1; then
    ok "boot-reassert agent installed + loaded (legacy)"
  else
    warn "could not load boot-reassert agent; check: launchctl print gui/$(id -u)/$REASSERT_LABEL"
  fi
}

reassert_uninstall() {
  log "removing boot-reassert LaunchAgent"
  if is_dry_run; then
    dim "[dry-run] launchctl bootout + rm $REASSERT_DEST"
    return 0
  fi
  launchctl bootout "gui/$(id -u)/$REASSERT_LABEL" >/dev/null 2>&1 \
    || launchctl unload "$REASSERT_DEST" >/dev/null 2>&1 || true
  launchctl bootout "gui/$(id -u)/$REASSERT_LABEL_OLD" >/dev/null 2>&1 || true
  rm -f "$REASSERT_DEST" "$HOME/Library/LaunchAgents/$REASSERT_LABEL_OLD.plist"
  ok "boot-reassert agent removed"
}

reassert_status() {
  local dm; dm="$(get_desired_mode)"; [ -z "$dm" ] && dm="(none)"
  if reassert_is_loaded; then
    echo "  boot re-assert: installed (will restore '$dm' on boot)"
  else
    echo "  boot re-assert: not installed"
  fi
}
