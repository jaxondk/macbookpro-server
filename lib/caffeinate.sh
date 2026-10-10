#!/usr/bin/env bash
# Manage the caffeinate LaunchAgent (user-level, NO sudo required).
# Sourced by bin/macsimize.
# shellcheck shell=bash

CAFF_LABEL="com.macsimize.caffeinate"
CAFF_LABEL_OLD="com.macbookpro-server.caffeinate"   # pre-rename; migrated away on install
CAFF_SRC="$REPO_ROOT/launchd/$CAFF_LABEL.plist"
CAFF_DEST="$HOME/Library/LaunchAgents/$CAFF_LABEL.plist"

caffeinate_install() {
  log "installing caffeinate LaunchAgent (user-level, no sudo)"
  run mkdir -p "$HOME/Library/LaunchAgents"
  # Migrate away from the pre-rename label if it's still around.
  if ! is_dry_run; then
    launchctl bootout "gui/$(id -u)/$CAFF_LABEL_OLD" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/LaunchAgents/$CAFF_LABEL_OLD.plist"
  fi
  run cp "$CAFF_SRC" "$CAFF_DEST"
  # bootout first in case it's already loaded (ignore failure), then bootstrap.
  if is_dry_run; then
    dim "[dry-run] launchctl bootout gui/\$(id -u)/$CAFF_LABEL  (if loaded)"
    dim "[dry-run] launchctl bootstrap gui/\$(id -u) $CAFF_DEST"
    return 0
  fi
  launchctl bootout "gui/$(id -u)/$CAFF_LABEL" >/dev/null 2>&1 || true
  if launchctl bootstrap "gui/$(id -u)" "$CAFF_DEST" 2>/dev/null; then
    ok "caffeinate agent loaded"
  elif launchctl load "$CAFF_DEST" >/dev/null 2>&1; then
    # Fallback for older macOS.
    ok "caffeinate agent loaded (legacy)"
  else
    warn "could not load caffeinate agent; check: launchctl print gui/$(id -u)/$CAFF_LABEL"
  fi
}

caffeinate_uninstall() {
  log "removing caffeinate LaunchAgent"
  if is_dry_run; then
    dim "[dry-run] launchctl bootout gui/\$(id -u)/$CAFF_LABEL"
    dim "[dry-run] rm -f $CAFF_DEST"
    return 0
  fi
  launchctl bootout "gui/$(id -u)/$CAFF_LABEL" >/dev/null 2>&1 \
    || launchctl unload "$CAFF_DEST" >/dev/null 2>&1 || true
  launchctl bootout "gui/$(id -u)/$CAFF_LABEL_OLD" >/dev/null 2>&1 || true
  rm -f "$CAFF_DEST" "$HOME/Library/LaunchAgents/$CAFF_LABEL_OLD.plist"
  ok "caffeinate agent removed"
}

caffeinate_is_loaded() { launchctl print "gui/$(id -u)/$CAFF_LABEL" >/dev/null 2>&1; }

caffeinate_status() {
  if caffeinate_is_loaded; then
    echo "  caffeinate agent: loaded"
  else
    echo "  caffeinate agent: not loaded"
  fi
}
