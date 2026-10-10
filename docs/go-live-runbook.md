# Go-live runbook — the steps that need you at the keyboard

Server mode (stay-awake + caffeinate guard) is already applied and verified. These are the remaining steps I deliberately did **not** do unattended, because they either need interactive sudo beyond `pmset`, or they can lock you/me out and need a second tailnet device to confirm. Do them in order. Each is reversible.

## 0. Prereqs (already true)

- Passwordless `pmset` grant installed (`scripts/sudoers-pmset` → `/etc/sudoers.d/…`). ✅
- `bin/macsimize status` shows `disablesleep 1`, caffeinate loaded, SSH on, Tailscale up. ✅

## 1. Verify "stays awake with the lid closed" (needs a 2nd device)

This is the one Layer-1 check that can't be scripted headlessly.

1. From your phone/another machine on the tailnet, confirm you can reach the box:
   ```sh
   ssh you@<tailscale-ip> 'echo ok; uptime'
   ```
2. **Close the laptop lid.** Wait ~2 minutes.
3. From the other device, run the same SSH again. It should still answer.
   - If it does: clamshell-headless works. 🎉
   - If it doesn't: the Mac slept. Re-open, run `bin/macsimize status`, and check `pmset -g | grep SleepDisabled` is `1`. (Some Macs also need "Prevent automatic sleeping when the display is off" toggled — but `disablesleep 1` normally supersedes it.)

## 2. SSH hardening (interactive sudo)

SSH is already on. To lock it to key-only (recommended even behind Tailscale):

```sh
scripts/ssh-enable-harden.sh --check      # report only, change nothing
scripts/ssh-enable-harden.sh              # ensure on + checks your authorized_keys
```

Then follow the printed manual steps to set `PasswordAuthentication no`. **Keep your current session open** and verify a fresh key-only login from another device before closing it, so a mistake can't lock you out. The script backs up `sshd_config` first.

## 3. Tailnet DNS + stable hostname — NOT NEEDED for this setup (2026-10-10)

Verified unnecessary: `accept-dns=false` is already set (TLS fix live), and connecting devices resolve `<host>.<tailnet>.ts.net` via their own Tailscale MagicDNS. Just connect by the stable IP `<tailscale-ip>` or that hostname. The script below is kept only for the case where an agent running *on this box* needs to resolve *other* `.ts.net` hosts by name.

Applies the fix from `../tailscale-claude-code-fix.md` *without* losing MagicDNS names:

```sh
scripts/dns-hostname-fix.sh               # shows current state + the exact plan
scripts/dns-hostname-fix.sh --apply       # executes (prompts for sudo on the resolver write)
```

Verify (some from the 2nd device):
```sh
/Applications/Tailscale.app/Contents/MacOS/Tailscale dns status     # DNS disabled
scutil --dns | grep -A2 ts.net                                      # ts.net resolver present
ping -c1 <host>.<your-tailnet>.ts.net                        # from another device
curl -sS -o /dev/null -w '%{http_code}\n' https://api.anthropic.com/ # not reset → TLS ok
```
If anything breaks connectivity, revert: `… Tailscale set --accept-dns=true` and `sudo rm /etc/resolver/ts.net`.

## 4. Make Tailscale an unattended server node (optional but recommended)

So the node's key doesn't expire and log the box off the tailnet:
- In the Tailscale admin console, disable key expiry for this machine, **or** tag it (e.g. `tag:server`) and bring it up with `tailscale up --ssh` so auth rides tailnet identity.

## 5. Planned-reboot drill (FileVault is on — Decision B)

Because FileVault is on, an unattended reboot stops at the unlock screen. For a *planned* reboot that comes back reachable without the keyboard:
```sh
sudo fdesetup authrestart          # unlocks once on the next boot; needs your disk password
```
For an *unexpected* reboot (power yank), expect to unlock at the keyboard once. On the mini, revisit this — see [`mac-mini-playbook.md`](mac-mini-playbook.md).

## 6. Flip back whenever you want

```sh
bin/macsimize laptop              # restores exact pre-server power settings, unloads guard
bin/macsimize status              # confirm
```

Running `macsimize laptop` does **not** turn SSH off (by design — harmless behind Tailscale). Turn it off manually if you want: `sudo systemsetup -setremotelogin off`.
