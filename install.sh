#!/usr/bin/env bash
#
# install.sh - sets up mac-ntfs-free: macFUSE + ntfs-3g, the CLI, and a
# background watcher that auto-remounts NTFS drives read-write whenever
# you plug them in.
#
# Safe to re-run - every step here is idempotent.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_SRC="$SCRIPT_DIR/bin/mac-ntfs-free"
PLIST_TEMPLATE="$SCRIPT_DIR/launchd/com.macntfsfree.watcher.plist.template"
PLIST_DEST="/Library/LaunchDaemons/com.macntfsfree.watcher.plist"

say()  { echo "==> $*"; }
warn() { echo "!!  $*" >&2; }

# ---------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found. Install it first from https://brew.sh, then re-run this script."
  exit 1
fi

# ---------------------------------------------------------------------
# 2. macFUSE
# ---------------------------------------------------------------------
say "Installing macFUSE (if needed)..."
if ! brew list --cask macfuse >/dev/null 2>&1; then
  brew install --cask macfuse
else
  say "macFUSE already installed."
fi

# ---------------------------------------------------------------------
# 3. ntfs-3g (from the gromgit/fuse tap - not in homebrew-core because
#    of its GPL license). Homebrew will refuse to run code from a new
#    third-party tap until you explicitly trust it - that's a deliberate
#    security gate, so we surface it instead of bypassing it.
# ---------------------------------------------------------------------
say "Installing ntfs-3g (if needed)..."
brew tap gromgit/fuse >/dev/null 2>&1 || true
if ! command -v ntfs-3g >/dev/null 2>&1; then
  if ! brew install ntfs-3g-mac; then
    warn "Homebrew may have blocked gromgit/fuse as an untrusted tap."
    warn "Run the 'brew trust ...' command it printed above, then re-run this script."
    exit 1
  fi
else
  say "ntfs-3g already installed."
fi

# ---------------------------------------------------------------------
# 4. Install the CLI
# ---------------------------------------------------------------------
BREW_BIN="$(brew --prefix)/bin"
say "Installing CLI to $BREW_BIN/mac-ntfs-free ..."
cp "$CLI_SRC" "$BREW_BIN/mac-ntfs-free"
chmod +x "$BREW_BIN/mac-ntfs-free"
CLI_PATH="$BREW_BIN/mac-ntfs-free"

# ---------------------------------------------------------------------
# 5. Install + load the watcher LaunchDaemon (needs root: it lives in
#    /Library/LaunchDaemons and must run as root so it can mount
#    without a password prompt every time you plug in a drive).
# ---------------------------------------------------------------------
say "Installing background watcher (requires sudo)..."
TMP_PLIST="$(mktemp)"
sed "s#__CLI_PATH__#${CLI_PATH}#g" "$PLIST_TEMPLATE" > "$TMP_PLIST"

sudo cp "$TMP_PLIST" "$PLIST_DEST"
sudo chown root:wheel "$PLIST_DEST"
sudo chmod 644 "$PLIST_DEST"
rm -f "$TMP_PLIST"

# unload first in case this is a re-install / upgrade
sudo launchctl unload "$PLIST_DEST" >/dev/null 2>&1 || true
sudo launchctl load -w "$PLIST_DEST"

# ---------------------------------------------------------------------
# 6. macFUSE system extension approval - this is the one step Apple
#    does not allow any script to do on your behalf. It requires a
#    physical click in System Settings.
# ---------------------------------------------------------------------
echo ""
if systemextensionsctl list 2>/dev/null | grep -qi fuse; then
  say "macFUSE system extension is already approved. You're all set."
else
  cat <<'EOF'
==> One manual step left (Apple requires this - no script can do it):

    1. Plug in an NTFS drive (or run: mac-ntfs-free mount "<VolumeName>")
    2. macOS will show a "System Extension Blocked" dialog for macFUSE
       (developer: Benjamin Fleischer). Click "Open System Settings".
    3. In Privacy & Security, click "Allow" next to macFUSE.
    4. Restart if prompted.
    5. Re-run this install.sh once more (it's safe to re-run) to confirm.

After that, every NTFS drive you plug in will mount read-write
automatically - no more manual steps.
EOF
fi

echo ""
say "Current status:"
"$CLI_PATH" status
