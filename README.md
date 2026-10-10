# macsimize

Turn a Mac into an always-on, [Tailnet](https://tailscale.com)-reachable server — then flip it back to a normal laptop with one command.

If you have a macOS machine you want to **act like a server** — and especially a **laptop** you want to leave running headless without it going to sleep or dropping off the network — this makes it behave like one. It stays awake (even with the lid shut), stays reachable over your private tailnet, and your remote sessions survive disconnects. Small, reversible, no OS wipe. Works on a spare MacBook today and a Mac mini later.

What you run the server *for* is up to you — see [Suggested setup](#suggested-setup) for the agentic-coding stack it was originally built for.

## Quick start

```sh
git clone https://github.com/jaxondk/macsimize ~/src/macsimize
cd ~/src/macsimize
scripts/setup            # installs + configures everything, asks a few preference questions
scripts/setup --dry-run  # or: see exactly what it would do, change nothing
scripts/setup --yes      # or: take the recommended default for every prompt
```

`setup` is turnkey: it installs and configures **Tailscale** (private address + SSH), installs **mosh** (resilient mobile sessions), enables **Remote Login**, asks about a couple of reboot-related preferences (below), flips the machine into server mode, and optionally installs a boot agent that re-asserts that mode after every reboot. Anything it can't do for you (a browser login, one GUI approval, a sudo grant) it prints at the end as a numbered checklist.

## Expected behavior

Once in server mode **on AC power**, the machine stays awake and reachable while you:

- **lock the screen**, let the **display sleep / turn off**, or **close the lid** (true clamshell — no external display needed).

Power and reboots:

- **Plugged in (AC):** never sleeps — that's the point. All settings are applied with `pmset -c` (**AC only**).
- **On battery (unplugged):** behaves like a normal laptop and sleeps as usual, so an unplugged laptop in a bag doesn't cook itself. The battery also acts as a built-in UPS, so a brief power blip won't drop the box (this is why a laptop makes a forgiving server; a Mac mini has no battery — see the mini playbook).
- **After a reboot:** the box powers back on and the boot agent re-applies whichever mode you were last in (server stays server). **But** if FileVault is on, it waits at the unlock screen until someone types the password — SSH and daemons don't start until then. For a *planned* reboot that comes back reachable without a keyboard: `sudo fdesetup authrestart`.

What it does **not** do: it won't keep the machine awake on battery, won't turn your display on, and won't change SSH, FileVault, or network settings beyond what you choose during setup.

## Preferences you choose at setup

A few things are personal-taste trade-offs between security and convenience, so `setup` asks instead of deciding for you (`--yes` takes the recommended default for each):

- **Disable automatic macOS updates** *(default: yes)* — auto-installed OS updates reboot the machine, which is the main cause of a surprise reboot that then stalls at the FileVault unlock screen. Security "rapid response" updates don't reboot and stay on.
- **FileVault** *(default: keep as-is; recommended ON for a laptop)* — ON means the disk is encrypted but a reboot needs a manual unlock; OFF means genuinely unattended reboots but an unencrypted boot disk. `setup` explains the trade-off and, because flipping it re-encrypts the whole disk, **prints the command** rather than doing it for you.
- **Boot re-assert agent** *(default: yes)* — a user-level LaunchAgent (no sudo) that re-applies your mode after every reboot/update, so you don't drift out of server mode.

## What this repo does — and what it doesn't

This repo is **only about making a machine behave like a server**. It is intentionally narrow, and it stands alone — you get a reachable, always-on box with no dev tools yet.

| ✅ This repo owns | ❌ Not this repo (your dotfiles own it) |
|---|---|
| Stay awake / lid-closed / survive reboots (`pmset`, caffeinate, boot re-assert) | Packages, Homebrew, shell, editors |
| Reachability: Tailscale server config, SSH, `mosh-server` | git identity, agent config (Claude Code etc.) |
| The reversible `server` ⇄ `laptop` toggle | Your terminal multiplexer of choice (tmux / herdr / phux) |
| Portability to a Mac mini | Anything about *what you do once you're connected* |

Where something straddles the line (Tailscale, mosh), this repo owns the **server-side configuration** and installs the binary if it's missing, so a clone-and-run works on a bare Mac. If your dotfiles already installed it, `setup` just detects it and moves on.

## Suggested setup

Your server can run anything — a build box, a home service, a media job. The reason this exists, though, is **agentic coding you drive from your phone**: kick off a long Claude Code / Codex / agent run on a machine you own, walk away, and check in, answer its prompts, and steer it from anywhere — sessions that survive disconnects.

For that, three pieces fit together:

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

## How it works

Server mode, on AC power only:

- A `pmset` profile that prevents sleep — including **lid-closed** (`disablesleep`) — keeps disk/network awake and enables power-on-after-failure.
- A user-level `caffeinate` LaunchAgent as a second keep-awake guard (no sudo).
- The chosen mode is recorded in `state/desired-mode`; a boot LaunchAgent re-applies *that* mode on every boot, so a reboot or a macOS update that resets `pmset` doesn't drift you out of the mode you were in.

The only privileged actions are `pmset` and (if you opt in) the auto-update toggle. FileVault is never changed automatically.

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
