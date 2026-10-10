# PLAN — Mac as a reversible, portable always-on devbox

The full design. For how to *use* what's built, see the top-level [`README.md`](../README.md); for the live status of the work, see [`PROGRESS.md`](PROGRESS.md); for the steps that still need you at the keyboard, see [`go-live-runbook.md`](go-live-runbook.md).

## Goal & constraints

- **Primary:** this MacBook Pro acts like an always-on server. Connect from phone / iPad / other laptop over the tailnet (Termius, etc.) and drive agentic coding sessions that survive disconnects.
- **Portable:** when the Mac mini arrives, clone this repo, run one script, server. Nothing hand-done that isn't captured here.
- **Reversible:** one command flips this laptop into "server mode" and another restores "laptop mode". No OS wipe; macOS stays macOS.
- **Out of scope:** dev-environment config (packages, shell, git, agentic tooling) is owned by your chezmoi [`~/dotfiles`](../../dotfiles) repo (canonical branch `chezmoi-migration`). This repo never duplicates a Brewfile or dotfile. On a new machine `chezmoi apply` does the dev env; this repo's `macsimize` does the server behavior.

## Decisions (made)

- **A — Config management: hybrid.** Plain shell scripts here now; package/dotfile layer stays in chezmoi; nix-darwin an optional Phase-2 migration of *that* layer later.
- **B — FileVault: stays on.** Manual unlock on the rare unexpected reboot; `fdesetup authrestart` for planned ones.
- **C — Hosting: local Mac only.** No cloud box. Hetzner (~€4/mo) kept as a documented fallback in [§ Hosted alternatives](#hosted-alternatives) if that ever changes.

These were the author's defaults, not law. The security-vs-convenience ones are personal taste, so `bin/macsimize setup` surfaces them as **prompts** (default = the recommended choice, `--yes` to accept all): disable auto-updates (default yes), keep FileVault on (default yes — never auto-toggled, since it re-encrypts the disk), and install the boot agent (default yes). See [`lib/prefs.sh`](../lib/prefs.sh).

## Session persistence: herdr (not raw tmux)

You already run **herdr** (agent-aware multiplexer; this repo was built from inside it, `HERDR_ENV=1`). It's the session layer — agents keep running when you disconnect and show per-agent state (blocked/working/done/idle). The plan references herdr as the persistence mechanism; `tmux`/`mosh` remain available as fallbacks. You may later swap to **phux** (mobile app + herdr-like server side); nothing here is coupled to herdr specifically, so a swap is just "use the other multiplexer" — the server layers are unaffected.

## The six layers

| # | Layer | Status |
|---|-------|--------|
| 1 | Stay awake & resilient | ✅ built + applied + live-verified |
| 2 | Remote access (Tailscale + SSH + mosh) | ✅ scripted install + config via `bin/macsimize setup`; browser login + key-expiry human-gated |
| 3 | Dev environment (herdr, agents, editors) | ➡️ owned by chezmoi dotfiles |
| 4 | Reversibility (`macsimize` toggle) | ✅ built + verified both directions (dry-run) |
| 5 | Portability (`bootstrap`, host profiles) | ✅ built; mini playbook written |
| 6 | Nice-to-haves (boot re-assert done; notifications/extra hardening later) | 🟡 partial |

### Layer 1 — Stay awake & resilient

A laptop is harder than a mini: it has a lid and a battery. The battery is a built-in UPS, so power-loss is a non-issue here (it matters on the mini). Server-mode applies, **AC only** (so an unplugged laptop in a bag still sleeps normally):

```
sudo pmset -c sleep 0 disksleep 0 powernap 0 womp 1 autorestart 1 disablesleep 1
```

- `disablesleep 1` is the key one for a laptop — stay awake with the **lid closed**, no external display (true clamshell-headless). Shows up as `SleepDisabled 1` in `pmset -g`.
- `autorestart 1` is a no-op on this laptop (not reported) but matters on the mini.
- A `caffeinate -s` **LaunchAgent** (user-level, no sudo) is the belt-and-suspenders guard; `-s` only asserts on AC, so battery behavior is untouched.

**Implemented by:** `bin/macsimize server` / `laptop` (snapshots originals to `state/pmset-restore.env` before first change; restore is exact).

**Verification (automatable, done):**
- `test/verify-offline.sh` — dry-run both directions, snapshot round-trip, shellcheck, plist lint.
- Live: `pmset -g | grep SleepDisabled` → `1`; `pmset -g assertions | grep PreventUserIdleSystemSleep`; `launchctl print gui/$(id -u)/com.macsimize.caffeinate` → running. **All confirmed.**

**Verification (needs you / a 2nd device):** close the lid and confirm the box stays reachable over the tailnet (`ssh`/ping) — inherently can't be tested headless-by-script. In [go-live-runbook](go-live-runbook.md).

> **FileVault caveat (Decision B).** With FileVault on, an *unattended* reboot stops at the unlock screen — SSH/daemons don't start until someone unlocks at the keyboard. Day-to-day (never rebooting, just staying awake) is unaffected. Planned reboots: `sudo fdesetup authrestart` comes back unlocked once.

### Layer 2 — Remote access over Tailnet

`bin/macsimize setup` makes this layer turnkey: it installs Tailscale (the **standalone** variant, `io.tailscale.ipn.macsys` — runs a system daemon, unlike the sandboxed App Store build) and `mosh` if missing, configures Tailscale for server use (`--ssh`, `--accept-dns=false`), and enables Remote Login — then prints the interactive remainder (browser login, key-expiry) as a checklist. Install lives here, not in dotfiles, because reachability is what makes the box a *server* (see [`lib/tailscale.sh`](../lib/tailscale.sh), [`lib/mosh.sh`](../lib/mosh.sh)); if dotfiles already brought the binary, setup detects and skips.

- **SSH:** Remote Login is enabled by `setup` (or `scripts/ssh-enable-harden.sh`). Hardening (key-only) is kept interactive, because disabling password auth wrong can lock you out; the script enables SSH and *prints* the hardening steps rather than auto-editing `sshd_config`.
- **Tailscale:** configured with `--ssh` and `--accept-dns=false` (the TLS fix). For a true server, make it an unattended node so its key doesn't expire (disable expiry in the admin console, or tag it), covered in the runbook.
- **mosh:** `mosh-server` is installed here so mobile clients ([Moshi](https://getmoshi.app), Blink) can use the mosh transport for resilient sessions over flaky mobile links. Carried over the tailnet, so no UDP ports to forward.
- **DNS / the ECONNRESET bug:** your [`tailscale-claude-code-fix.md`](../../tailscale-claude-code-fix.md) shows `--accept-dns=true` breaks Claude Code TLS. `scripts/dns-hostname-fix.sh` applies the clean fix: `--accept-dns=false` **plus** `/etc/resolver/ts.net` → so you keep a stable `.ts.net` hostname *and* working TLS. Network-sensitive → human-gated, verify from a 2nd device.
- **mosh** available for flaky mobile links; **Termius** is your phone client.

### Layer 3 — Dev environment → owned by chezmoi dotfiles

Out of scope here. `bootstrap` only *checks* that `herdr`, `git`, `claude`, etc. are present and tells you to run `chezmoi apply` if not. Anything server-specific that's missing gets fixed in dotfiles, not here.

### Layer 4 — Reversibility (the toggle)

`bin/macsimize server|laptop|status [--dry-run]`:
- **server** — snapshot (once) → apply AC power profile → load caffeinate agent → print status.
- **laptop** — unload caffeinate agent → restore the snapshot exactly → print status.
- **status** — read-only, no sudo; shows power keys, caffeinate, SSH, Tailscale.

Design rules: idempotent, snapshot-before-change, `--dry-run` prints every command, no silent sudo. The only privileged call is `pmset` (covered by the scoped passwordless grant, `scripts/sudoers-pmset`); the caffeinate agent is user-level (no sudo).

### Layer 5 — Portability to the Mac mini

`scripts/bootstrap` detects host profile (laptop vs desktop via battery presence), checks prereqs + the pmset grant, and can flip to server mode (`--server`). The mini needs the same scripts plus the extra bits in [`mac-mini-playbook.md`](mac-mini-playbook.md): `autorestart` actually works there, plus "Start up after power failure" in Energy settings, and it's the case where `fdesetup authrestart` / FileVault choices really bite (no battery, truly headless).

### Layer 6 — Nice-to-haves

- **Boot re-assert (done).** `macsimize boot-agent install` sets up a user LaunchAgent that, on every login/boot, re-applies whichever mode was last set (`state/desired-mode`): server restores server, laptop restores laptop. Insurance against macOS updates silently resetting `pmset`. No sudo (uses the existing `pmset` grant). Both directions verified live.
- **Still optional/later:** agent push notifications (ntfy/Pushover or a Claude Code `Stop` hook); SSH key-only + Tailscale ACLs; Time Machine/NAS backup.

## Hosted alternatives

Reference only (Decision C = local). For a *Linux* devbox, **Hetzner** is the value king (~€4/mo CX23: 2 vCPU/4 GB; ~€6.50/mo CX33) — flat-rate, always-on, no lid/battery/FileVault quirks. Fly.io is only cheaper if the box sleeps most of the time. A *cloud Mac* (MacStadium / EC2 Mac) is $60–150+/mo because of Apple's dedicated-hardware licensing — not worth it versus owning the mini. If you ever want an always-reliable companion, a €4 Hetzner box is the pick, and the dotfiles/approach port to it.

## Sources

Captured in the first commit's research: remote-CC-over-Tailscale blogs (redock.dev, ronnierocha.dev, harperfoley.com), headless-Mac power/boot (hometechops, arda.pw), FileVault vs unattended reboot (Apple Dev Forums, Jamf), nix-darwin trade-offs (carette.xyz, tale.me), hosted cost (getdeploying, bex.co), herdr overview (tecmint, betterstack).
