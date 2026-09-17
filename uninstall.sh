#!/usr/bin/env bash
#
# uninstall.sh - removes the mac-ntfs-free watcher and CLI. Leaves
# macFUSE/ntfs-3g installed by default (pass --remove-deps to also
# uninstall those via Homebrew).
#
set -uo pipefail

PLIST_DEST="/Library/LaunchDaemons/com.macntfsfree.watcher.plist"

say() { echo "==> $*"; }

say "Stopping and removing watcher daemon..."
sudo launchctl unload "$PLIST_DEST" >/dev/null 2>&1 || true
sudo rm -f "$PLIST_DEST"

BREW_BIN="$(brew --prefix 2>/dev/null)/bin"
if [[ -n "${BREW_BIN:-}" && -f "$BREW_BIN/mac-ntfs-free" ]]; then
  say "Removing CLI from $BREW_BIN/mac-ntfs-free ..."
  rm -f "$BREW_BIN/mac-ntfs-free"
fi

sudo rm -rf /var/run/mac-ntfs-free
sudo rm -f /Library/Logs/mac-ntfs-free.log

if [[ "${1:-}" == "--remove-deps" ]]; then
  say "Removing macFUSE and ntfs-3g..."
  brew uninstall --cask macfuse 2>&1 || true
  brew uninstall ntfs-3g-mac 2>&1 || true
fi

echo ""
say "Uninstalled. Any drives currently mounted read-write via ntfs-3g will"
say "revert to macOS's native read-only mount next time you reconnect them."
