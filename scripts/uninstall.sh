#!/usr/bin/env bash
# Removes MenuBarClear, its settings and its privacy permissions.
set -uo pipefail

BUNDLE_ID="io.github.aafs-ops.MenuBarClear"

pkill -x MenuBarClear 2>/dev/null
rm -rf "/Applications/MenuBarClear.app" "$HOME/Applications/MenuBarClear.app"
defaults delete "$BUNDLE_ID" 2>/dev/null
tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1

# Pre-1.0 development builds.
launchctl bootout "gui/$(id -u)/local.menubarclear" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/local.menubarclear.plist"

echo "✓ MenuBarClear removed."
echo "  If it was set to launch at login, also remove it in System Settings → General → Login Items."
