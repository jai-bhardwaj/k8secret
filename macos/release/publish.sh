#!/bin/bash
# Build, package, and publish a new K8Secret release to Azure Blob Storage
#
# Prerequisites:
#   brew install azure-cli
#   npm install -g appdmg  (optional, falls back to hdiutil)
#   az login
#
# Usage:
#   ./publish.sh <version> [release notes]
#   ./publish.sh 0.2.4
#   ./publish.sh 0.2.4 "Fixed pod log streaming"

set -euo pipefail

VERSION="${1:?Usage: ./publish.sh <version> [release notes]}"
NOTES="${2:-K8Secret v${VERSION}}"
STORAGE_ACCOUNT="${K8SECRET_STORAGE_ACCOUNT:-orbitalk8releases}"
CONTAINER="k8secret-releases"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$MACOS_DIR")"
APP_BUNDLE="$ROOT_DIR/build/K8Secret.app"
DMG_PATH="$MACOS_DIR/dmg/K8Secret-${VERSION}.dmg"

echo "==> Building K8Secret v${VERSION}"

# Step 1: Bump version in AppConstants.swift
CONSTANTS="$MACOS_DIR/Sources/K8Secret/AppConstants.swift"
sed -i '' "s/static let version = \".*\"/static let version = \"${VERSION}\"/" "$CONSTANTS"
echo "    Updated AppConstants.swift"

# Step 2: Bump version in Info.plist
PLIST="$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
echo "    Updated Info.plist"

# Step 3: Build release binary
echo "==> Compiling (release)..."
cd "$MACOS_DIR"
swift build -c release 2>&1 | tail -3

# Step 4: Copy binary into .app bundle
BINARY="$MACOS_DIR/.build/arm64-apple-macosx/release/K8Secret"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/k8secret"
echo "    Copied binary to app bundle"

# Step 5: Ensure Info.plist has ATS exception
if ! /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity" "$PLIST" &>/dev/null; then
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" "$PLIST"
    echo "    Added ATS exception to Info.plist"
fi

# Step 6: Ad-hoc code sign
codesign --force --deep --sign - "$APP_BUNDLE"
echo "    Signed app bundle (ad-hoc)"

# Step 7: Create DMG with Applications shortcut
echo "==> Creating DMG..."
rm -f "$DMG_PATH"
STAGING="$(mktemp -d)"
cp -R "$APP_BUNDLE" "$STAGING/K8Secret.app"
xattr -cr "$STAGING/K8Secret.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "K8Secret" -fs HFS+ -srcfolder "$STAGING" -ov "$DMG_PATH"
rm -rf "$STAGING"
echo "    Created $DMG_PATH"

# Step 8: Upload to Azure
echo "==> Uploading to Azure..."
az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --name "K8Secret-${VERSION}.dmg" \
    --file "$DMG_PATH" \
    --overwrite

# Step 9: Update manifest
cat > /tmp/k8secret-latest.json <<EOF
{
  "version": "${VERSION}",
  "url": "https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/K8Secret-${VERSION}.dmg",
  "notes": "${NOTES}",
  "minOS": "14.0",
  "date": "$(date +%Y-%m-%d)"
}
EOF

az storage blob upload \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --name "latest.json" \
    --file "/tmp/k8secret-latest.json" \
    --overwrite \
    --content-type "application/json" \
    --content-cache-control "no-cache, no-store, must-revalidate"

rm /tmp/k8secret-latest.json

echo ""
echo "==> K8Secret v${VERSION} published!"
echo "    Manifest: https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/latest.json"
echo "    DMG:      https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/K8Secret-${VERSION}.dmg"
