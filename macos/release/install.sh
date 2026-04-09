#!/bin/bash
# K8Secret installer — run with:
#   curl -fsSL https://orbitalk8releases.blob.core.windows.net/k8secret-releases/install.sh | bash
set -euo pipefail

APP_NAME="K8Secret"
CONTAINER_URL="https://orbitalk8releases.blob.core.windows.net/k8secret-releases"
INSTALL_DIR="/Applications"

echo "Fetching latest version..."
MANIFEST=$(curl -fsSL "$CONTAINER_URL/latest.json")
VERSION=$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])")
DMG_URL=$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
NOTES=$(echo "$MANIFEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['notes'])")

echo "Installing $APP_NAME v$VERSION..."
echo "  $NOTES"
echo ""

# Download DMG
TMP_DMG=$(mktemp /tmp/K8Secret-XXXXX.dmg)
curl -fSL --progress-bar "$DMG_URL" -o "$TMP_DMG"

# Mount silently
MOUNT_DIR=$(hdiutil attach "$TMP_DMG" -nobrowse -noverify -noautoopen 2>/dev/null | grep "Volumes" | awk -F'\t' '{print $NF}')

# Remove old version if exists
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "Removing previous version..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

# Copy app
echo "Installing to $INSTALL_DIR..."
cp -R "$MOUNT_DIR/$APP_NAME.app" "$INSTALL_DIR/"

# Strip quarantine and sign
xattr -cr "$INSTALL_DIR/$APP_NAME.app"
codesign --force --deep --sign - "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null

# Cleanup
hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null
rm -f "$TMP_DMG"

echo ""
echo "K8Secret v$VERSION installed successfully!"
echo "Open from Applications or run: open -a K8Secret"
