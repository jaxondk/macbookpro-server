# macbookpro-server

Turn a Mac into an always-on, [Tailnet](https://tailscale.com)-reachable server — then flip it back to a normal laptop with one command.

**Why:** so you can run **agentic coding sessions on a machine you own** and drive them from your phone or another device — kick off a long Claude Code / Codex / agent run, walk away, and check in, answer its prompts, and steer it from anywhere. The box stays awake (even lid-closed), stays reachable over your private tailnet, and your sessions survive disconnects. Small, reversible, no OS wipe. Works on a spare MacBook today and a Mac mini later.

## Quick start

```sh
git clone https://github.com/jaxondk/macbookpro-server ~/src/macbookpro-server
cd ~/src/macbookpro-server
scripts/setup            # installs + configures everything; prints the few steps only you can do
scripts/setup --dry-run  # or: see exactly what it would do, change nothing
```

`setup` is turnkey: it installs and configures **Tailscale** (private address + SSH), installs **mosh** (resilient mobile sessions), enables **Remote Login**, flips the machine into server mode, and installs a boot agent that re-asserts that mode after every reboot. Anything it can't do for you (a browser login, one GUI approval, a sudo grant) it prints at the end as a numbered checklist.

## What this repo does — and what it doesn't

This repo is **only about making a machine behave like a server**. It is intentionally narrow, and it stands alone — you get a reachable, always-on box with no dev tools yet.

| ✅ This repo owns | ❌ Not this repo (your dotfiles own it) |
|---|---|
| Stay awake / lid-closed / survive reboots (`pmset`, caffeinate, boot re-assert) | Packages, Homebrew, shell, editors |
| Reachability: Tailscale server config, SSH, `mosh-server` | git identity, agent config (Claude Code etc.) |
| The reversible `server` ⇄ `laptop` toggle | Your terminal multiplexer of choice (tmux / herdr / phux) |
| Portability to a Mac mini | Anything about *what you do once you're connected* |

Where something straddles the line (Tailscale, mosh), this repo owns the **server-side configuration** and installs the binary if it's missing, so a clone-and-run works on a bare Mac. If your dotfiles already installed it, `setup` just detects it and moves on.

## Suggested setup: a phone-driven devbox

This repo is one of three pieces. Together they turn a Mac into a devbox you run from your pocket:

1. **this repo** → the machine stays on and reachable.
2. **a dotfiles repo** → your dev environment (packages, shell, editors, agents). Use something like [chezmoi](https://chezmoi.io); drive persistent sessions with a multiplexer like [herdr](https://github.com/steveyegge/herdr) or phux so agents keep running after you disconnect. Example: [github.com/jaxondk/dotfiles](https://github.com/jaxondk/dotfiles).
3. **a mobile client** → [**Moshi**](https://getmoshi.app) ([App Store](https://apps.apple.com/app/id6757859949)) is purpose-built for this: a phone terminal for long-running coding agents on your own machine, with an approvals inbox and push notifications. It connects over the tailnet using the **mosh** transport this repo installs. (Any mosh/SSH client works — e.g. [Blink](https://blink.sh) — Moshi is just the most on-point for agent workflows. If you use Moshi's agent inbox, also install its `moshi-hook` on the host per [their docs](https://getmoshi.app/docs/introduction).)

## Commands

```sh
bin/servermode server    # stay awake (even lid-closed), keep-awake guard, remember the mode
bin/servermode laptop    # restore your original sleep/battery behavior
bin/servermode status    # what mode am I in?  (read-only, no sudo)
```

`scripts/setup` runs the full first-time setup; `servermode` is the day-to-day toggle once reachability is configured.

## Steps only you can do

A few things can't be scripted safely or at all. `setup` prints these as a checklist when it finishes; in full they are:

- **Log in to Tailscale** — `tailscale up --ssh --accept-dns=false` opens a browser login (and, on a fresh install, a one-time System Settings approval of its system extension).
- **Disable key expiry** for this node in the [Tailscale admin console](https://login.tailscale.com/admin/machines) (or tag it) so a headless box never logs itself off the tailnet.
- **Install the `pmset` grant** (one sudo prompt) if you want the toggle to run without a password — see [Usage](#usage) below.
- **Unlock after a reboot** — with FileVault on, a reboot waits at the unlock screen until someone types the password. For a *planned* reboot that comes back ready: `sudo fdesetup authrestart`.
- **Optional:** lock SSH to key-only (`scripts/ssh-enable-harden.sh`) — kept manual because getting it wrong can lock you out. Low-stakes since the box is tailnet-only, not public.

## Usage

The one optional manual step worth doing up front — let this user run `pmset` without a password, so toggling needs no prompt (`__USER__` is filled in automatically):

```sh
sed "s/__USER__/$(id -un)/" scripts/sudoers-pmset > /tmp/sm-sudoers && \
  sudo visudo -cf /tmp/sm-sudoers && \
  sudo install -m 0440 -o root -g wheel /tmp/sm-sudoers /etc/sudoers.d/macbookpro-server-pmset && \
  rm -f /tmp/sm-sudoers
```

Then connect from another device over the tailnet (`ssh you@<tailscale-ip>` or the MagicDNS name, or via Moshi/Blink over mosh) and work inside your multiplexer.

## How it works

Server mode, on AC power only (so an unplugged laptop still sleeps normally):

- A `pmset` profile that prevents sleep — including **lid-closed** (`disablesleep`) — keeps disk/network awake and enables power-on-after-failure.
- A user-level `caffeinate` LaunchAgent as a second keep-awake guard (no sudo).
- The chosen mode is recorded in `state/desired-mode`; a boot LaunchAgent re-applies *that* mode on every boot, so a reboot or a macOS update that resets `pmset` doesn't drift you out of the mode you were in — server restores server, laptop restores laptop.

The only privileged action is `pmset` (covered by the scoped grant above). FileVault is never changed automatically.

## Safe & reversible

- Your original power settings are snapshotted before any change; `bin/servermode laptop` restores them exactly.
- Every script has a `--dry-run` (prints commands, changes nothing) and a read-only `status` / `--check`.
- To undo everything:
  ```sh
  bin/servermode laptop
  bin/servermode boot-agent remove
  sudo rm /etc/sudoers.d/macbookpro-server-pmset   # if you installed the grant
  ```

## Portability

The repo *is* the portability story — clone it on another Mac and run `scripts/setup`. It detects laptop vs desktop (e.g. a Mac mini) and applies the right profile. See [`docs/mac-mini-playbook.md`](docs/mac-mini-playbook.md) for the mini's extra bits (power-failure restart, FileVault trade-offs).

More detail: [`docs/PLAN.md`](docs/PLAN.md) (design + decisions), [`docs/PROGRESS.md`](docs/PROGRESS.md) (build log), [`docs/go-live-runbook.md`](docs/go-live-runbook.md) (the human-gated steps).

## Contributing

Heads up: this was built for one person's setup, so it is **not** written to be highly general yet — some things still assume specifics (a few macOS-version behaviors, Apple-Silicon-leaning power settings, Homebrew for installs, the `com.macbookpro-server.*` LaunchAgent naming). That's exactly where help is most valuable: **if you hit a spot that assumes something specific to its author's machine, please open an issue or PR to make it more general** (parameterize it, detect it, document it). Smallest useful contribution: point at the line that wouldn't work on your machine and say why.
