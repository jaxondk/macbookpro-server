# macbookpro-server

Make a Mac behave like an always-on, [Tailnet](https://tailscale.com)-reachable server — and flip it back to a normal laptop with one command. Small, reversible, no OS wipe. Built for turning a spare MacBook (or a Mac mini) into a devbox you SSH into from your phone or another machine to run agentic coding sessions that survive disconnects.

```sh
bin/servermode server    # stay awake (even lid-closed), keep-awake guard, remember the mode
bin/servermode laptop    # restore your original sleep/battery behavior
bin/servermode status    # what mode am I in?  (read-only, no sudo)
```

## Pair it with a dotfiles repo = a macOS devbox

This repo only handles **server behavior** (staying awake, reachability, the reversible toggle). It deliberately does **not** manage your dev environment — packages, shell, editors, agent config. Pair it with a dotfiles repo for that half, and together you get a full devbox out of a Mac:

- **dotfiles** (e.g. via [chezmoi](https://chezmoi.io)) → your tools and config. Example: [github.com/jaxondk/dotfiles](https://github.com/jaxondk/dotfiles).
- **this repo** → makes the machine stay on and reachable.

On a fresh Mac: `chezmoi apply` (dev env), then `scripts/bootstrap --server` (server behavior).

## Requirements

- macOS (Apple Silicon or Intel), a user account you can SSH into.
- [Tailscale](https://tailscale.com) installed and logged in (gives the box a private, stable address without exposing it to the internet).
- A terminal multiplexer to keep sessions alive across disconnects — [tmux](https://github.com/tmux/tmux), herdr, or similar.

## Usage

```sh
# 1. (optional) let this user run `pmset` without a password, so toggling needs no prompt.
#    (__USER__ is filled in with your username automatically.)
sed "s/__USER__/$(id -un)/" scripts/sudoers-pmset > /tmp/sm-sudoers && \
  sudo visudo -cf /tmp/sm-sudoers && \
  sudo install -m 0440 -o root -g wheel /tmp/sm-sudoers /etc/sudoers.d/macbookpro-server-pmset && \
  rm -f /tmp/sm-sudoers

# 2. go
scripts/bootstrap                 # checks prerequisites, prints next steps
bin/servermode server             # flip to server mode
bin/servermode boot-agent install # re-assert your mode on every boot (optional, recommended)
test/verify-offline.sh            # safe self-checks, change nothing
```

Then connect from another device over the tailnet (`ssh you@<tailscale-ip>` or the MagicDNS name) and work inside your multiplexer. See [`docs/go-live-runbook.md`](docs/go-live-runbook.md) for optional SSH hardening and a tailnet-hostname tweak.

## How it works

Server mode, on AC power only (so an unplugged laptop still sleeps normally):

- `pmset` profile that prevents sleep, including **lid-closed** (`disablesleep`), keeps disk/network awake, and enables power-on-after-failure.
- A user-level `caffeinate` LaunchAgent as a second keep-awake guard (no sudo).
- Records the chosen mode in `state/desired-mode`; a boot LaunchAgent re-applies that mode on every boot (survives reboots and macOS updates that reset `pmset`). It restores *whatever mode you were last in* — server or laptop.

The only privileged action is `pmset`; everything else is user-level. SSH config, FileVault, and Tailscale are never changed automatically.

## Safe & reversible

- Your original power settings are snapshotted before any change; `bin/servermode laptop` restores them exactly.
- Every script has a `--dry-run` (prints commands, changes nothing) and a read-only `status`/`--check`.
- To undo everything:
  ```sh
  bin/servermode laptop
  bin/servermode boot-agent remove
  sudo rm /etc/sudoers.d/macbookpro-server-pmset   # if you installed the grant
  ```

## Portability

The repo is the portability story — clone it on another Mac and run `scripts/bootstrap --server`. It detects laptop vs desktop (e.g. a Mac mini) and applies the right profile. See [`docs/mac-mini-playbook.md`](docs/mac-mini-playbook.md) for the mini's extra bits (power-failure restart, FileVault trade-offs).

More detail: [`docs/PLAN.md`](docs/PLAN.md) (design + decisions), [`docs/PROGRESS.md`](docs/PROGRESS.md) (build log).

## Contributing

Heads up: this was built for one person's setup, so it is **not** written to be highly general yet — some things still assume specifics (a few macOS-version behaviors, Apple-Silicon-leaning power settings, the `com.macbookpro-server.*` LaunchAgent naming). That's exactly where help is most valuable: **if you hit a spot that assumes something specific to its author's machine, please open an issue or PR to make it more general** (parameterize it, detect it, document it). Smallest useful contribution: point at the line that wouldn't work on your machine and say why.
