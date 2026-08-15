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

json_field() {
    # Read one top-level string field from the manifest on stdin, without
    # depending on python3 (not present on a stock macOS install).
    /usr/bin/sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1
}

echo "Fetching latest version..."
MANIFEST="$(curl -fsSL "$MANIFEST_URL")"
VERSION="$(printf '%s' "$MANIFEST" | json_field version)"
DMG_URL="$(printf '%s' "$MANIFEST" | json_field url)"
NOTES="$(printf '%s' "$MANIFEST" | json_field notes)"
EXPECTED_SHA="$(printf '%s' "$MANIFEST" | json_field sha256)"

[[ -n "$VERSION" && -n "$DMG_URL" ]] || { echo "Could not read the release manifest." >&2; exit 1; }

# The manifest is remote data. Only fetch over HTTPS from the release host.
case "$DMG_URL" in
    https://github.com/jai-bhardwaj/k8secret/releases/download/*) ;;
    *) echo "Refusing to install: unexpected download URL '$DMG_URL'." >&2; exit 1 ;;
esac

if [[ ! "$EXPECTED_SHA" =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo "Refusing to install: manifest has no sha256 checksum to verify against." >&2
    exit 1
fi

echo "Installing $APP_NAME v$VERSION..."
[[ -n "$NOTES" ]] && echo "  $NOTES"
echo ""

# Download DMG
TMP_DMG="$(mktemp /tmp/K8Secret-XXXXX.dmg)"
cleanup() { rm -f "$TMP_DMG"; }
trap cleanup EXIT
curl -fSL --progress-bar "$DMG_URL" -o "$TMP_DMG"

# Verify before doing anything that executes the contents.
ACTUAL_SHA="$(shasum -a 256 "$TMP_DMG" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
    echo "Checksum mismatch — refusing to install." >&2
    echo "  expected: $EXPECTED_SHA" >&2
    echo "  actual:   $ACTUAL_SHA" >&2
    exit 1
fi
echo "✓ Checksum verified"

# Quit running instance, if any
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Quitting running $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
fi

# Mount (DMG checksum verification left on)
MOUNT_DIR="$(hdiutil attach "$TMP_DMG" -nobrowse -noautoopen 2>/dev/null | grep "Volumes" | awk -F'\t' '{print $NF}')"
[[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR/$APP_NAME.app" ]] || {
    echo "Could not find $APP_NAME.app in the downloaded disk image." >&2
    [[ -n "$MOUNT_DIR" ]] && hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
    exit 1
}
cleanup() { hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true; rm -f "$TMP_DMG"; }

# Stage the new version alongside the old one, then swap. The previous install is
# only removed once the replacement is on disk, so a failure here can't leave the
# machine with no app at all.
STAGED="$INSTALL_DIR/.$APP_NAME.app.incoming"
rm -rf "$STAGED"
echo "Installing to $INSTALL_DIR..."
cp -R "$MOUNT_DIR/$APP_NAME.app" "$STAGED"

if [[ -d "$INSTALL_DIR/$APP_NAME.app" ]]; then
    echo "Removing previous version..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi
mv "$STAGED" "$INSTALL_DIR/$APP_NAME.app"

# If the build is properly signed and notarized, leave Gatekeeper alone — it can
# validate the app on its own, which is the whole point of notarizing. Only fall
# back to stripping quarantine for ad-hoc builds, which Gatekeeper would block.
if spctl --assess --type execute "$INSTALL_DIR/$APP_NAME.app" >/dev/null 2>&1; then
    echo "✓ Notarized build — Gatekeeper checks left intact"
else
    # No re-sign here: the app is already ad-hoc signed at publish time and
    # ad-hoc signing is deterministic, so re-signing reproduced the same
    # signature. Clearing quarantine is the only step Gatekeeper cares about
    # for an un-notarized app.
    echo "  Ad-hoc build: clearing quarantine so it will launch"
    xattr -cr "$INSTALL_DIR/$APP_NAME.app"
fi

# Unmount (also handled by the EXIT trap on any early failure)
hdiutil detach "$MOUNT_DIR" -quiet
rm -f "$TMP_DMG"
trap - EXIT

echo ""
echo "✓ $APP_NAME v$VERSION installed."
echo "  Launch with: open -a $APP_NAME"
