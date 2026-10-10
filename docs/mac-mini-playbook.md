# Mac mini playbook — differences from the laptop

When the Mac mini arrives, it becomes the real always-on server. The whole repo ports as-is; this doc lists only what's *different* from the MacBook.

## Same as the laptop

```sh
# 1. dev env (owned by dotfiles)
chezmoi init --apply <your-dotfiles-repo>
# 2. server behavior (this repo)
git clone <this repo> ~/src/macbookpro-server && cd ~/src/macbookpro-server
scripts/bootstrap            # detects profile = "desktop" (no battery)
sed "s/__USER__/$(id -un)/" scripts/sudoers-pmset > /tmp/sm-sudoers && \
  sudo visudo -cf /tmp/sm-sudoers && \
  sudo install -m 0440 -o root -g wheel /tmp/sm-sudoers /etc/sudoers.d/macbookpro-server-pmset && rm -f /tmp/sm-sudoers
bin/servermode boot-agent install   # re-assert mode on every boot
bin/servermode server
```

(`scripts/bootstrap --server` does the `boot-agent install` + `servermode server` in one step.)

`host_profile()` returns **desktop** on the mini (no `InternalBattery`), so the scripts know they're on the real server.

## What's different

1. **No lid, no battery.** `disablesleep` is irrelevant (no clamshell); the point is simply `sleep 0`. There's no battery UPS, so **power-loss resilience matters** — the opposite of the laptop.

2. **`autorestart` actually works.** On the laptop it's a no-op; on the mini `sudo pmset -c autorestart 1` (already in the server profile) makes it power back on after a power loss. Also set it in the GUI: **System Settings → Energy → "Start up automatically after a power failure."**

3. **FileVault decision may want revisiting.** The laptop keeps FileVault on (Decision B) because it's portable/stealable. A mini locked in your home is lower-risk, so you *might* choose to disable FileVault there to get genuinely unattended reboots (daemons + SSH come back with nothing plugged in). Trade-off: unencrypted boot disk. If you keep FileVault on, an unexpected reboot still needs a manual unlock — fine if you rarely reboot, annoying for a headless box you can't easily reach. `sudo fdesetup authrestart` covers planned reboots.

4. **Truly headless.** No built-in display. Confirm Screen Sharing/VNC is available as a fallback in case SSH ever fails. Apple Silicon can "park" a headless display; the caffeinate LaunchAgent in this repo guards against that.

5. **Caffeinate guard still applies** but is less critical once `sleep 0` + no lid is in play; keep it as belt-and-suspenders.

6. **Rename.** Give it a distinct `LocalHostName` (e.g. `mac-mini-server`) so tailnet names don't collide with the laptop:
   ```sh
   sudo scutil --set LocalHostName mac-mini-server
   sudo scutil --set ComputerName  mac-mini-server
   ```

## Verification on the mini

Same `test/verify-offline.sh`, plus the live checks in [`go-live-runbook.md`](go-live-runbook.md). The reboot drill is the important one here: do a **real** `sudo fdesetup authrestart` (or plain `sudo reboot` if FileVault is off) and confirm the box comes back reachable over the tailnet **with only power + ethernet/Wi-Fi attached, nothing else**. That's the proof it's a real server.
