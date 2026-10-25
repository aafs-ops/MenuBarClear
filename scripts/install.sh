#!/usr/bin/env bash
# Installs build/MenuBarClear.app into /Applications and launches it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/MenuBarClear.app"
DEST="/Applications/MenuBarClear.app"

[ -d "$SRC" ] || { echo "Build first: make app"; exit 1; }

pkill -x MenuBarClear 2>/dev/null || true

# Clean up the LaunchAgent and copy used by pre-1.0 development builds.
OLD_AGENT="$HOME/Library/LaunchAgents/local.menubarclear.plist"
if [ -f "$OLD_AGENT" ]; then
    launchctl bootout "gui/$(id -u)/local.menubarclear" 2>/dev/null || true
    rm -f "$OLD_AGENT"
fi
rm -rf "$HOME/Applications/MenuBarClear.app"

rm -rf "$DEST"
ditto "$SRC" "$DEST"
echo "✓ Installed to $DEST"

open "$DEST"
cat <<'EOF'

First launch: allow MenuBarClear in
  System Settings → Privacy & Security → Screen & System Audio Recording
  System Settings → Privacy & Security → Accessibility
then choose "Restart" from the MenuBarClear menu bar icon.

Rebuilt from source? macOS treats every new ad-hoc build as a new app:
remove the old MenuBarClear entries in both lists (–) and allow it again.
EOF
