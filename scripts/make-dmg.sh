#!/usr/bin/env bash
# Builds build/MenuBarClear-<version>.dmg from build/MenuBarClear.app:
# a drag-to-install window with a custom background, the app on the left,
# an Applications shortcut on the right and the app icon as the volume icon.
#
# Uses only tools that ship with macOS (hdiutil, tiffutil, osascript, xattr).
# The window layout is applied through Finder, so the first run may ask to let
# Terminal control Finder: allow it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
NAME="MenuBarClear"
APP="build/$NAME.app"
DMG="build/$NAME-$VERSION.dmg"
VOLNAME="$NAME"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# Window geometry (points) — must match scripts/dmg-background.swift.
WIN_W=640; WIN_H=400; WIN_X=200; WIN_Y=140
ICON_SIZE=128
APP_X=160; APPS_X=480; ICONS_Y=205

[ -d "$APP" ] || { echo "Build the app first: make app"; exit 1; }

WORK="$(mktemp -d)"
STAGE="$WORK/stage"
RW_DMG="$WORK/rw.dmg"
cleanup() {
    [ -n "${MOUNT:-}" ] && hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "→ Staging"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
# Retina background: drawn by scripts/dmg-background.swift at 1x + 2x,
# combined into one multi-resolution TIFF.
if ! xcrun --find swiftc >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
xcrun swiftc -O -swift-version 5 scripts/dmg-background.swift -o "$WORK/dmg-background"
"$WORK/dmg-background" "$WORK/bg.png" "$WORK/bg@2x.png"
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

echo "→ Creating writable image"
# Unmount any leftover volume with the same name so Finder targets the right one.
if [ -d "/Volumes/$VOLNAME" ]; then hdiutil detach "/Volumes/$VOLNAME" -force -quiet || true; fi
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
    -format UDRW -size "${SIZE_MB}m" "$RW_DMG"

MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" \
    | grep -E '/Volumes/' | sed -E 's|.*(/Volumes/.*)$|\1|' | head -n1)"
[ -d "$MOUNT" ] || { echo "Failed to mount image"; exit 1; }
DISK_NAME="$(basename "$MOUNT")"

# Custom volume icon: set the "has custom icon" Finder flag on the volume root.
xattr -wx com.apple.FinderInfo \
    "0000000000000000040000000000000000000000000000000000000000000000" "$MOUNT"

echo "→ Laying out window"
osascript <<EOF
tell application "Finder"
    tell disk "$DISK_NAME"
        open
        set theWindow to container window
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set pathbar visible of theWindow to false
        set bounds of theWindow to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H))}
        set viewOptions to icon view options of theWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON_SIZE
        set text size of viewOptions to 13
        set label position of viewOptions to bottom
        set shows item info of viewOptions to false
        set shows icon preview of viewOptions to false
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "$NAME.app" of theWindow to {$APP_X, $ICONS_Y}
        set position of item "Applications" of theWindow to {$APPS_X, $ICONS_Y}
        set extension hidden of item "$NAME.app" of theWindow to true
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Hide the support files and make sure Finder's .DS_Store is written.
chflags hidden "$MOUNT/.background" "$MOUNT/.VolumeIcon.icns" 2>/dev/null || true
rm -rf "$MOUNT/.fseventsd" 2>/dev/null || true
sync; sleep 1

hdiutil detach "$MOUNT" -quiet
MOUNT=""

echo "→ Compressing"
rm -f "$DMG"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"

if [ "$SIGN_IDENTITY" != "-" ]; then
    echo "→ Signing DMG"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "✓ $DMG"
shasum -a 256 "$DMG"
