# Progress log

Newest first. Issue IDs are beads (`bd show <id>`).

## 2026-10-10 (later still) — boot re-assert agent

- Built **boot re-assert** (Layer 6): `servermode boot-agent install` loads a user LaunchAgent that on each boot re-applies `state/desired-mode` (written by `servermode server|laptop`). Mode-aware: server→server, laptop→laptop; no-op if unset. No sudo (uses the `pmset` grant).
- New files: `lib/reassert.sh`, `scripts/boot-reassert.sh`, `launchd/com.macbookpro-server.boot-reassert.plist` (path templated at install). `servermode` gained `boot-agent install|remove` + a status line + a clear verdict header; `bootstrap --server` now installs it.
- **Verified live both directions:** forced desired=laptop → agent restored LAPTOP; desired=server → restored SERVER. Installed + loaded on this box; machine left in SERVER mode. Offline harness green.

## 2026-10-10 (later) — go-live outcome

- **Lid-closed reachability test: PASSED.** User closed the lid; box stayed reachable over the tailnet. Clamshell-headless server confirmed working for real.
- **TLS/ECONNRESET fix: already live.** `tailscale dns status` shows DNS disabled (`accept-dns=false` already set); IPv6 HTTPS to api.anthropic.com returns `HTTP 404` in ~0.04s (no reset). Nothing to apply.
- **DNS/hostname fix (`4sd`): closed as not-needed.** MagicDNS is enabled tailnet-wide; connecting devices (phone) resolve `<host>.<tailnet>.ts.net` via their own Tailscale. `/etc/resolver/ts.net` would only help this box resolve *other* `.ts.net` hosts — not the connect-into-it workflow. Connect by stable IP `<tailscale-ip>` or the MagicDNS name; client (Termius/mosh/phux) makes no difference.
- **SSH key-only hardening (`bpz`): deferred by user.** Box is tailnet-only (not public), so password auth is low-risk. Optional hygiene for later.

Net: the devbox is fully usable as intended. Only optional hardening remains.

**Reboot/uptime hardening (done this session):**
- **Tailscale key expiry: DISABLED** (user, via admin console). Confirmed `Self.KeyExpiry` now empty — headless node won't get logged off the tailnet (was expiring 2026-11-08).
- **Unattended macOS-update reboots: OFF.** Set `com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates = 0` (verified). Security-data/response updates left on (they don't reboot). This removes the main surprise-reboot cause on a laptop (battery already covers power loss), so the FileVault-unlock-on-boot wall is now only hit on *deliberate* reboots.
- `status` command improved: leading `SERVER/LAPTOP` verdict line; `autorestart` annotated as n/a on laptops.

## 2026-10-10 — core server layer built, applied, verified

**Done (autonomous, while user AFK):**
- Repo scaffolding, git, beads issue tracking (9 issues).
- Split docs: `README.md` → traditional readme; full plan → `docs/PLAN.md`; this log.
- `bin/servermode server|laptop|status [--dry-run]` + `lib/{common,power,caffeinate}.sh`.
  - Power profile applied **for real** (AC only): `sleep 0 disksleep 0 powernap 0 womp 1 autorestart 1 disablesleep 1`. Baseline snapshotted to `state/pmset-restore.env` first.
  - **Live-verified:** `pmset -g` → `SleepDisabled 1`; `PreventUserIdleSystemSleep` assertion held; caffeinate LaunchAgent running (pid confirmed). (closes `k61`, `en0`)
- `scripts/bootstrap` with laptop-vs-desktop host detection + prereq/grant checks. (closes `ljg`)
- `test/verify-offline.sh` — shellcheck, `bash -n`, `plutil -lint`, dry-run both directions, snapshot round-trip. **All green.** (closes `fes`)
- `scripts/sudoers-pmset` — scoped passwordless `pmset`. **User installed it** (confirmed `sudo -n pmset` works), which unlocked the real apply above.
- Gated scripts written (not executed): `scripts/ssh-enable-harden.sh`, `scripts/dns-hostname-fix.sh`. (notes on `bpz`, `4sd`)
- Docs: `docs/go-live-runbook.md`, `docs/mac-mini-playbook.md`.
- Installed `shellcheck` via brew (verification tool).

**Decisions locked:** A=hybrid scripts, B=keep FileVault on, C=local Mac only.

**Context captured:** session persistence = **herdr** (running inside it; `HERDR_ENV=1`), with phux as a possible future swap; phone client = Termius. Dev env is owned by chezmoi dotfiles (`chezmoi-migration` branch) — out of scope for this repo.

**Changed on the machine (all reversible):**
- `sudo pmset -c …` server profile (revert: `bin/servermode laptop`).
- `~/Library/LaunchAgents/com.macbookpro-server.caffeinate.plist` loaded (revert: same).
- `/etc/sudoers.d/macbookpro-server-pmset` installed by user (revert: `sudo rm` it).
- Nothing touched: FileVault, SSH config, Tailscale DNS, network.

**Left for the user (human-gated — see go-live-runbook):**
- Lid-closed-stays-reachable test (needs 2nd device). — open follow-up
- SSH key-only hardening (`bpz`). — interactive
- Tailnet DNS/hostname fix (`4sd`). — network-sensitive, needs 2nd device
- Tailscale unattended-node / key-expiry-off (optional).
- `docs` issue `s1z` closed by this restructure; `5ek`/`4zl` closed by the two new docs.
