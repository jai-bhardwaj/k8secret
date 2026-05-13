#!/usr/bin/env bash
# Build, package, and publish a new K8Secret release to GitHub Releases.
#
# Prerequisites:
#   brew install gh jq
#   gh auth login
#
# Usage:
#   ./macos/release/publish.sh <version> [release notes]
#   ./macos/release/publish.sh 0.5.3
#   ./macos/release/publish.sh 0.5.3 "Fixed pod log streaming"

set -euo pipefail

VERSION="${1:?Usage: ./publish.sh <version> [release notes]}"
NOTES="${2:-K8Secret v${VERSION}}"
TAG="v${VERSION}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$MACOS_DIR")"
RELEASE_DIR="$ROOT_DIR/release"
APP_BUNDLE="$ROOT_DIR/build/K8Secret.app"
DMG_PATH="$MACOS_DIR/dmg/K8Secret-${VERSION}.dmg"

# Sanity checks
if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh CLI not found. Install with: brew install gh" >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq not found. Install with: brew install jq" >&2
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "Error: gh CLI not authenticated. Run: gh auth login" >&2
    exit 1
fi
if git -C "$ROOT_DIR" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: Tag $TAG already exists. Bump the version." >&2
    exit 1
fi
if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
    echo "Warning: working tree is dirty. Continue? [y/N]"
    read -r REPLY
    [[ "$REPLY" =~ ^[Yy]$ ]] || exit 1
fi

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

# Step 5: Ensure Info.plist has ATS exception (preserves backward compat)
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

# Step 8: Compute sha256 (for release notes only — installer trusts HTTPS + git)
SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo "    sha256: $SHA"

# Step 9: Commit version bump + tag
cd "$ROOT_DIR"
git add "$CONSTANTS"
git diff --cached --quiet || git commit -m "release: bump to ${VERSION}"
git tag "$TAG"

# Step 10: Create GitHub release with DMG attached
echo "==> Creating GitHub release..."
gh release create "$TAG" "$DMG_PATH" \
    --title "K8Secret ${VERSION}" \
    --notes "${NOTES}

sha256: \`${SHA}\`

Install:
\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/jai-bhardwaj/k8secret/main/release/install.sh | bash
\`\`\`"

# Step 11: Update release/latest.json so the installer + in-app updater pick this up
echo "==> Updating manifest..."
mkdir -p "$RELEASE_DIR"
TODAY="$(date +%Y-%m-%d)"
DMG_URL="https://github.com/jai-bhardwaj/k8secret/releases/download/${TAG}/K8Secret-${VERSION}.dmg"
jq -n \
    --arg version "$VERSION" \
    --arg url "$DMG_URL" \
    --arg notes "$NOTES" \
    --arg date "$TODAY" \
    '{
        version: $version,
        url: $url,
        notes: $notes,
        minOS: "14.0",
        date: $date
    }' > "$RELEASE_DIR/latest.json"

git add "$RELEASE_DIR/latest.json"
git commit -m "release: ${VERSION} manifest"

# Step 12: Push commits + tag so the manifest and release are both live
git push
git push --tags

echo ""
echo "==> K8Secret v${VERSION} published."
echo "    Release: https://github.com/jai-bhardwaj/k8secret/releases/tag/${TAG}"
echo "    DMG:     $DMG_URL"
