#!/usr/bin/env bash
# System-preference decisions offered at setup time. These are matters of taste
# (security vs. convenience), so scripts/setup ASKS rather than imposing them.
# Sourced after lib/common.sh.
# shellcheck shell=bash

SU_DOMAIN="/Library/Preferences/com.apple.SoftwareUpdate"

# --- macOS automatic updates -------------------------------------------------
# Auto-installed OS updates REBOOT the machine — the main cause of a surprise
# reboot that then stalls at the FileVault unlock screen on a headless box.
# (Security "rapid response" updates are separate and don't reboot; left on.)
autoupdate_is_disabled() {
  [ "$(defaults read "$SU_DOMAIN" AutomaticallyInstallMacOSUpdates 2>/dev/null)" = "0" ]
}
autoupdate_disable() {
  log "disabling automatic macOS update installs (prevents surprise reboots)"
  run sudo defaults write "$SU_DOMAIN" AutomaticallyInstallMacOSUpdates -bool false
  ok "automatic macOS update installs OFF (security rapid-responses stay on)"
}

# --- FileVault ---------------------------------------------------------------
# We never toggle FileVault automatically — enabling/disabling re-encrypts the
# whole disk, which is slow and not something to spring on someone's machine.
# setup detects the state, explains the trade-off, and prints the command.
filevault_is_on() { fdesetup status 2>/dev/null | grep -q "FileVault is On"; }
filevault_status_line() {
  if filevault_is_on; then
    echo "  FileVault: ON  (disk encrypted; a reboot waits for a manual unlock)"
  else
    echo "  FileVault: off (unattended reboots work; boot disk is unencrypted)"
  fi
}
