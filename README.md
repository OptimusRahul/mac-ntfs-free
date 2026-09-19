# mac-ntfs-free

Free, open-source NTFS read/write for macOS. No license fee, no
subscription — built entirely on top of [macFUSE](https://macfuse.github.io/)
and [ntfs-3g](https://github.com/tuxera/ntfs-3g), with a background
watcher so your Windows-formatted drives mount read-write automatically
every time you plug them in.

## The problem this solves

Plug a Windows-formatted (NTFS) external drive into a Mac and macOS
mounts it **read-only** by default — you can read files but can't copy
anything onto it, rename, or delete. The usual fix is a paid driver
(Paragon NTFS for Mac, Tuxera NTFS, ~$20-40). This does the same job
for free.

It's a real, common problem — macOS Tahoe in particular broke a wave
of existing NTFS tools (kext-based drivers no longer load the way they
used to), so there's an active cluster of 2026 how-tos and forum
threads about drives silently going read-only again after an update.

## How it works

- **[macFUSE](https://macfuse.github.io/)** — the modern (System
  Extension / FSKit-based, not kext) userspace filesystem framework
  for macOS.
- **[ntfs-3g](https://github.com/tuxera/ntfs-3g)** — the actual NTFS
  read/write driver, running in userspace on top of macFUSE.
- **A LaunchDaemon watcher** — runs as root in the background, notices
  whenever macOS mounts a new NTFS volume read-only, and immediately
  remounts it read-write via ntfs-3g. This is necessary because on
  current macOS the classic "replace `/sbin/mount_ntfs`" trick no
  longer works — `/sbin` lives on the cryptographically sealed system
  volume and can't be written to, even as root, even with SIP
  relaxed. A watcher daemon is the only mechanism strong enough to do
  this "for you" without your having to remount by hand every time.

## Install

```bash
git clone https://github.com/OptimusRahul/mac-ntfs-free.git
cd mac-ntfs-free
./install.sh
```

Requires [Homebrew](https://brew.sh). The script:
1. Installs macFUSE (`brew install --cask macfuse`)
2. Installs ntfs-3g (`brew tap gromgit/fuse && brew install ntfs-3g-mac`)
3. Installs the `mac-ntfs-free` CLI
4. Installs and loads a LaunchDaemon that watches `/Volumes` and
   auto-remounts any read-only NTFS drive it finds

It's safe to re-run at any point.

### One manual step (Apple requires this — no installer can skip it)

The first time macFUSE tries to actually mount something, macOS shows
a **"System Extension Blocked"** dialog. This is expected, and it's
the real macFUSE (developer: Benjamin Fleischer) being blocked by
Apple's security gate, not a bug:

1. Plug in an NTFS drive, or run `mac-ntfs-free mount "<VolumeName>"`.
2. Click **Open System Settings** in the dialog.
3. Under **Privacy & Security**, click **Allow** next to macFUSE.
4. Restart if prompted.
5. Re-run `./install.sh` once more to confirm everything's wired up.

After that, it's invisible — plug in any NTFS drive and it mounts
read-write on its own.

## Usage

```bash
mac-ntfs-free status          # macFUSE approval, daemon state, mounted volumes
mac-ntfs-free mount "<Name>"  # manually force one volume read-write
```

Everything else is automatic via the background watcher.

## Uninstall

```bash
./uninstall.sh                # removes the watcher + CLI
./uninstall.sh --remove-deps  # also removes macFUSE + ntfs-3g via Homebrew
```

## Troubleshooting

- **`mac-ntfs-free status` shows the daemon not loaded** — re-run
  `./install.sh`; the `sudo launchctl load` step may have failed
  silently if you cancelled a password prompt.
- **Drive still read-only after plugging in** — check
  `/Library/Logs/mac-ntfs-free.log` for errors from `ntfs-3g` (a
  common cause is a dirty NTFS journal — plug the drive into a Windows
  PC once and let it run `chkdsk`, or eject cleanly rather than
  yanking it in future).
- **"macFUSE is out of date" / version mismatch error** — macFUSE and
  ntfs-3g-mac must stay in version lockstep (ntfs-3g-mac is built
  against macFUSE's headers/library), so re-run `./install.sh`: it
  detects whichever one is outdated — including macFUSE, whose cask is
  marked `auto_updates` so a plain `brew outdated` misses it — and
  upgrades it automatically. If macOS then shows a fresh system
  extension approval dialog, allow it and re-run the command — a
  macFUSE upgrade sometimes requires re-approval even if it was
  approved before.
- **"untrusted tap" error during install** — Homebrew is deliberately
  blocking a third-party tap (`gromgit/fuse`) until you explicitly
  trust it. Run the exact `brew trust ...` command it prints, then
  re-run `./install.sh`.
- **Extension approval screen not where you expect** — the exact menu
  path shifts between macOS versions; use the System Settings search
  bar and type "extensions" or "macfuse", or trigger the dialog again
  and click straight through via its own "Open System Settings"
  button.

## Why this over paid drivers

Paragon/Tuxera NTFS drivers are legitimate products, but on current
macOS (Tahoe) they've had real compatibility problems — kext-based
drivers not loading, volumes silently falling back to Apple's
read-only reader. This project trades a small amount of one-time setup
friction (the extension approval Apple requires) for a $0, fully
open-source stack that you can inspect, fix, and rebuild yourself.

## License

MIT — see [LICENSE](LICENSE). ntfs-3g itself is GPL-licensed; this
repo only shells out to the `ntfs-3g` binary, it doesn't link against
or redistribute it.
