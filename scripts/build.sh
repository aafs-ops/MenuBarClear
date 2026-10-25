#!/usr/bin/env bash
# Builds build/MenuBarClear.app
#
#   ARCHS="arm64 x86_64"   architectures to build (default: this Mac's)
#   SIGN_IDENTITY="…"      codesign identity (default: "-" = ad-hoc)
#
# Needs Xcode or the Command Line Tools (xcode-select --install).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-$(uname -m)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
MIN_MACOS="14.0"

OUT="$ROOT/build"
APP="$OUT/MenuBarClear.app"
OBJ="$OUT/obj"

# A broken or mismatched Xcode install makes xcrun fail; fall back to the Command Line Tools.
if ! xcrun --find swiftc >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"

echo "→ MenuBarClear $VERSION ($BUILD_NUMBER) for: $ARCHS"
rm -rf "$APP" "$OBJ"
mkdir -p "$OBJ" "$APP/Contents/MacOS" "$APP/Contents/Resources"

BINARIES=()
for ARCH in $ARCHS; do
    echo "  • compiling $ARCH"
    xcrun swiftc \
        -O -whole-module-optimization -swift-version 5 \
        -target "$ARCH-apple-macos$MIN_MACOS" \
        -sdk "$SDK" \
        -framework AppKit -framework ScreenCaptureKit -framework ServiceManagement \
        -o "$OBJ/MenuBarClear-$ARCH" \
        Sources/MenuBarClear/*.swift
    BINARIES+=("$OBJ/MenuBarClear-$ARCH")
done

if [ "${#BINARIES[@]}" -gt 1 ]; then
    xcrun lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/MenuBarClear"
else
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/MenuBarClear"
fi

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "  • signing ($SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

rm -rf "$OBJ"
echo "✓ $APP"
