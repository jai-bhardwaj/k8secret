#!/usr/bin/env bash
# K8Secret installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jai-bhardwaj/k8secret/main/release/install.sh | bash
#
# Reads the manifest at release/latest.json, downloads the DMG from
# GitHub Releases, copies K8Secret.app into /Applications, and strips
# the quarantine bit so Gatekeeper doesn't prompt (the app is ad-hoc
# signed, not notarized).

set -euo pipefail

APP_NAME="K8Secret"
INSTALL_DIR="/Applications"
MANIFEST_URL="https://raw.githubusercontent.com/jai-bhardwaj/k8secret/main/release/latest.json"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "K8Secret currently runs on macOS only. Windows + Linux are on the roadmap." >&2
    exit 1
fi

echo "Fetching latest version..."
MANIFEST="$(curl -fsSL "$MANIFEST_URL")"
VERSION="$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])")"
DMG_URL="$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")"
NOTES="$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('notes',''))")"

echo "Installing $APP_NAME v$VERSION..."
[[ -n "$NOTES" ]] && echo "  $NOTES"
echo ""

# Download DMG
TMP_DMG="$(mktemp /tmp/K8Secret-XXXXX.dmg)"
curl -fSL --progress-bar "$DMG_URL" -o "$TMP_DMG"

# Quit running instance, if any
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Quitting running $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
fi

# Mount silently
MOUNT_DIR="$(hdiutil attach "$TMP_DMG" -nobrowse -noverify -noautoopen 2>/dev/null | grep "Volumes" | awk -F'\t' '{print $NF}')"

# Remove old version if exists
if [[ -d "$INSTALL_DIR/$APP_NAME.app" ]]; then
    echo "Removing previous version..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

# Copy app
echo "Installing to $INSTALL_DIR..."
cp -R "$MOUNT_DIR/$APP_NAME.app" "$INSTALL_DIR/"

# Strip quarantine and re-sign ad-hoc so Gatekeeper stays quiet
xattr -cr "$INSTALL_DIR/$APP_NAME.app"
codesign --force --deep --sign - "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

# Unmount
hdiutil detach "$MOUNT_DIR" -quiet
rm -f "$TMP_DMG"

echo ""
echo "✓ $APP_NAME v$VERSION installed."
echo "  Launch with: open -a $APP_NAME"
