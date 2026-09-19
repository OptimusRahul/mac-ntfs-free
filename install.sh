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
# 2. macFUSE + ntfs-3g, kept in version lockstep. ntfs-3g-mac is built
#    against macFUSE's headers/library, so an outdated macFUSE paired
#    with a newer ntfs-3g (or vice versa) is exactly what produces the
#    "macFUSE version" / mount errors people hit - upgrading only one
#    side leaves them incompatible. Every check below upgrades in place
#    when it finds a mismatch, then re-verifies before moving on.
# ---------------------------------------------------------------------
brew update >/dev/null 2>&1 || true

say "Checking macFUSE..."
if ! brew list --cask macfuse >/dev/null 2>&1; then
  say "macFUSE not installed - installing the latest version..."
  brew install --cask macfuse
else
  # macFUSE's cask is marked auto_updates, so plain `brew outdated` skips
  # it unless told to check auto-updating casks too.
  if [[ -n "$(brew outdated --cask --greedy macfuse 2>/dev/null)" ]]; then
    installed_ver="$(brew list --cask --versions macfuse 2>/dev/null | awk '{print $2}')"
    say "macFUSE $installed_ver is outdated - upgrading to the latest version..."
    if brew upgrade --cask macfuse; then
      say "macFUSE upgraded. You may need to re-approve the system extension"
      say "in Privacy & Security (see step 5 below) even if it was approved before."
    else
      warn "Automatic macFUSE upgrade failed. Run 'brew upgrade --cask macfuse' manually and re-run this script."
      exit 1
    fi
  else
    say "macFUSE is up to date."
  fi
fi

# ntfs-3g comes from the gromgit/fuse tap - not in homebrew-core because
# of its GPL license. Homebrew will refuse to run code from a new
# third-party tap until you explicitly trust it - that's a deliberate
# security gate, so we surface it instead of bypassing it.
say "Checking ntfs-3g..."
brew tap gromgit/fuse >/dev/null 2>&1 || true
if ! brew list ntfs-3g-mac >/dev/null 2>&1; then
  say "ntfs-3g not installed - installing the latest version..."
  if ! brew install ntfs-3g-mac; then
    warn "Homebrew may have blocked gromgit/fuse as an untrusted tap."
    warn "Run the 'brew trust ...' command it printed above, then re-run this script."
    exit 1
  fi
else
  outdated_check="$(brew outdated ntfs-3g-mac 2>&1)"
  if [[ "$outdated_check" == *"untrusted tap"* ]]; then
    warn "Homebrew is blocking the compatibility check on ntfs-3g (gromgit/fuse) as an untrusted tap:"
    echo "$outdated_check" | grep -i 'brew trust' >&2
    warn "Run that command, then re-run this script so ntfs-3g can be verified/upgraded against the current macFUSE."
    exit 1
  elif [[ -n "$outdated_check" ]]; then
    say "ntfs-3g is outdated - upgrading to stay compatible with the current macFUSE..."
    if ! brew upgrade ntfs-3g-mac; then
      warn "Automatic ntfs-3g upgrade failed. Run 'brew upgrade ntfs-3g-mac' manually and re-run this script."
      exit 1
    fi
  else
    say "ntfs-3g is up to date."
  fi
fi

if ! command -v ntfs-3g >/dev/null 2>&1; then
  warn "ntfs-3g still not found on PATH after install/upgrade."
  exit 1
fi

# ---------------------------------------------------------------------
# 3. Install the CLI
# ---------------------------------------------------------------------
BREW_BIN="$(brew --prefix)/bin"
say "Installing CLI to $BREW_BIN/mac-ntfs-free ..."
cp "$CLI_SRC" "$BREW_BIN/mac-ntfs-free"
chmod +x "$BREW_BIN/mac-ntfs-free"
CLI_PATH="$BREW_BIN/mac-ntfs-free"

# ---------------------------------------------------------------------
# 4. Install + load the watcher LaunchDaemon (needs root: it lives in
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
# 5. macFUSE system extension approval - this is the one step Apple
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
