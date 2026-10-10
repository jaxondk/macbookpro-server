#!/usr/bin/env bash
# The `macsimize setup` orchestrator. Sourced by bin/macsimize, which defines
# cmd_server / cmd_status / reassert_install and sources the reachability + prefs
# libs this uses. Runs with errexit OFF so a soft failure in one step becomes a
# checklist item instead of aborting the whole setup.
#
# DRY_RUN / ASSUME_YES / _c_* colors live in lib/common.sh (sourced by the
# entrypoint before this); ShellCheck can't follow that, hence the disables.
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

_SETUP_MANUAL=()
setup_manual() { _SETUP_MANUAL+=("$*"); }

cmd_setup() {
  set +e  # tolerate per-step failures; we collect them as manual steps
  local arg
  for arg in "$@"; do
    case "$arg" in
      --yes|-y)  ASSUME_YES=1 ;;
      --dry-run) DRY_RUN=1 ;;
      "" ) ;;
      *) die "unknown setup flag: $arg (try --yes, --dry-run)" ;;
    esac
  done
  # A dry run shouldn't block on prompts; use the recommended defaults.
  is_dry_run && ASSUME_YES=1
  _SETUP_MANUAL=()

  log "macsimize setup — host profile: $(host_profile)  ($(scutil --get LocalHostName 2>/dev/null || echo '?'))"
  is_dry_run && warn "DRY-RUN: no changes will be made"
  echo

  # --- 1. Tailscale (reachability) ------------------------------------------
  log "1/6  Tailscale — private, stable address to reach this box"
  local fresh_ts=0
  if tailscale_is_installed; then
    ok "already installed ($(ts_bin))"
  elif is_dry_run; then
    dim "[dry-run] would install standalone Tailscale (brew install --cask tailscale)"
  elif tailscale_install; then
    fresh_ts=1
  else
    setup_manual "Install Tailscale (standalone) from https://tailscale.com/download/macos, then re-run: bin/macsimize setup"
  fi

  if tailscale_is_installed && [ "$fresh_ts" = "0" ]; then
    if is_dry_run; then
      dim "[dry-run] would run: tailscale set --ssh=true --accept-dns=false"
    elif tailscale_is_up; then
      tailscale_configure && ok "Tailscale configured for server use"
    else
      warn "Tailscale is installed but not logged in."
      setup_manual "Authenticate + configure Tailscale:  $(ts_bin) up --ssh --accept-dns=false   (opens a browser login)"
    fi
  elif [ "$fresh_ts" = "1" ]; then
    warn "Tailscale was just installed — a one-time GUI approval is required."
    setup_manual "Open Tailscale.app once and approve the system extension / VPN config in System Settings, then run:  $(ts_bin) up --ssh --accept-dns=false"
  fi
  setup_manual "In the Tailscale admin console, DISABLE key expiry for this machine (or tag it) so a headless node never logs itself off the tailnet."
  echo

  # --- 2. mosh-server (reachability for mobile clients) ---------------------
  log "2/6  mosh — resilient mobile sessions (Moshi, Blink, …)"
  if is_dry_run; then
    if mosh_is_installed; then ok "mosh-server present"; else dim "[dry-run] would install mosh (brew install mosh)"; fi
  else
    mosh_install || setup_manual "Install mosh:  brew install mosh"
  fi
  echo

  # --- 3. SSH / Remote Login ------------------------------------------------
  log "3/6  SSH — enable Remote Login"
  if is_dry_run; then
    dim "[dry-run] would enable Remote Login (scripts/ssh-enable-harden.sh; prompts for sudo)"
  elif launchctl print system/com.openssh.sshd >/dev/null 2>&1; then
    ok "Remote Login already ON"
  elif ask_yn "Enable SSH / Remote Login (needed to connect in)" y; then
    "$REPO_ROOT/scripts/ssh-enable-harden.sh" || setup_manual "Enable SSH manually:  sudo systemsetup -setremotelogin on"
  else
    setup_manual "Enable SSH when ready:  scripts/ssh-enable-harden.sh"
  fi
  setup_manual "Optional hardening: lock SSH to key-only (lockout risk, do it carefully):  scripts/ssh-enable-harden.sh --check  then follow its printed steps."
  echo

  # --- 4. Reboot-surprise preferences (your call) ---------------------------
  log "4/6  Preferences — reduce surprise reboots (your call)"
  if autoupdate_is_disabled; then
    ok "automatic macOS updates already disabled"
  elif is_dry_run; then
    dim "[dry-run] would offer to disable automatic macOS updates (default: yes)"
  elif ask_yn "Disable automatic macOS updates? They reboot the box unexpectedly (recommended for a server)" y; then
    autoupdate_disable || setup_manual "Disable auto-updates:  sudo defaults write $SU_DOMAIN AutomaticallyInstallMacOSUpdates -bool false"
  else
    dim "leaving automatic macOS updates as-is (expect occasional reboots)."
  fi

  echo
  dim "$(filevault_status_line)"
  if filevault_is_on; then
    dim "  ON keeps a portable/stealable laptop safe, but a reboot stops at the unlock"
    dim "  screen until someone types the password (SSH/daemons don't start until then)."
    if is_dry_run; then
      dim "[dry-run] would ask whether to keep FileVault on (default: keep on)"
    elif ask_yn "Keep FileVault ON? (recommended for a laptop)" y; then
      ok "keeping FileVault on"
      setup_manual "For a PLANNED reboot that returns reachable without a keyboard:  sudo fdesetup authrestart"
    else
      warn "turning FileVault off re-encrypts the whole disk — not something this script will do for you."
      setup_manual "Turn FileVault OFF yourself (slow; unencrypts the boot disk, enables unattended reboots):  sudo fdesetup disable"
    fi
  else
    dim "  off means reboots come back unattended, but the boot disk is unencrypted."
  fi
  echo

  # --- 5. Boot re-assert agent (your call) ----------------------------------
  log "5/6  Boot re-assert agent — re-apply your mode after every reboot/update"
  local want_boot_agent=0
  if is_dry_run; then
    dim "[dry-run] would offer to install the boot re-assert agent (default: yes)"
    want_boot_agent=1
  elif ask_yn "Install the boot re-assert agent? Re-applies server/laptop mode on each boot (no sudo)" y; then
    want_boot_agent=1
  else
    dim "skipping the boot agent — a reboot won't re-apply server mode on its own."
  fi

  # --- 6. Server mode -------------------------------------------------------
  log "6/6  Server mode — stay awake (lid-close safe)"
  [ "$want_boot_agent" = "1" ] && reassert_install
  cmd_server

  # pmset grant note (install is sensitive → printed, not auto-run).
  if ! sudo -n pmset -g >/dev/null 2>&1; then
    setup_manual "Optional: install the scoped pmset grant so toggling needs no password (one sudo prompt; grants NOPASSWD for /usr/bin/pmset ONLY):
    sed \"s/__USER__/\$(id -un)/\" scripts/sudoers-pmset > /tmp/sm-sudoers && \\
      sudo visudo -cf /tmp/sm-sudoers && \\
      sudo install -m 0440 -o root -g wheel /tmp/sm-sudoers /etc/sudoers.d/macsimize-pmset && \\
      rm -f /tmp/sm-sudoers"
  fi
  echo

  # --- Summary --------------------------------------------------------------
  if [ "${#_SETUP_MANUAL[@]}" -gt 0 ]; then
    printf '%s==> STEPS ONLY YOU CAN DO%s  (the rest is done)\n' "$_c_yellow" "$_c_reset"
    local n=1 m
    for m in "${_SETUP_MANUAL[@]}"; do
      printf '  %d. %s\n' "$n" "$m"
      n=$((n + 1))
    done
  else
    ok "nothing left for you to do — fully set up."
  fi
  echo
  dim "Reverse everything:  bin/macsimize laptop  &&  bin/macsimize boot-agent remove"
}
