#!/usr/bin/env bash
# Build, package, and publish a new K8Secret release to GitHub Releases.
#
# This script is self-contained: it builds the .app bundle from scratch
# on every run (no need for a pre-existing build/K8Secret.app skeleton),
# so any clean clone can produce a release as long as Xcode + the toolchain
# below are installed.
#
# Prerequisites (one-time setup):
#   1. Install Xcode (full app, not just CLT — SwiftUI builds need the
#      full macOS SDK that ships with Xcode):
#        open "macappstore://apps.apple.com/app/xcode/id497799835"
#   2. Point xcode-select at Xcode:
#        sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer
#        sudo xcodebuild -license accept
#   3. Install brew tools:
#        brew install gh jq
#        gh auth login
#
# Usage:
#   ./macos/release/publish.sh <version> [release notes]
#   ./macos/release/publish.sh 0.5.2
#   ./macos/release/publish.sh 0.5.3 "Fixed pod log streaming"

set -euo pipefail

VERSION="${1:?Usage: ./publish.sh <version> [release notes]}"
NOTES="${2:-K8Secret v${VERSION}}"
TAG="v${VERSION}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$MACOS_DIR")"
RELEASE_DIR="$ROOT_DIR/release"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/K8Secret.app"
DMG_PATH="$MACOS_DIR/dmg/K8Secret-${VERSION}.dmg"
PLIST_TEMPLATE="$SCRIPT_DIR/Info.plist.template"
ICON_PATH="$SCRIPT_DIR/AppIcon.icns"

step() { printf "\n==> %s\n" "$*"; }
ok()   { printf "    ✓ %s\n" "$*"; }
fail() { printf "\n✗ %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
step "Preflight"

command -v gh >/dev/null 2>&1   || fail "gh CLI not found. brew install gh"
command -v jq >/dev/null 2>&1   || fail "jq not found. brew install jq"
command -v swift >/dev/null 2>&1 || fail "swift not found in PATH"
gh auth status >/dev/null 2>&1  || fail "gh CLI not authenticated. gh auth login"

# Xcode must be selected — Command Line Tools alone can't build SwiftUI apps
XCODE_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
case "$XCODE_DEV_DIR" in
    *Xcode.app/Contents/Developer*) ok "Xcode active at $XCODE_DEV_DIR" ;;
    *) fail "Xcode (full app) is not active. Currently using: ${XCODE_DEV_DIR:-none}
   Install Xcode from the App Store, then:
     sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer
     sudo xcodebuild -license accept" ;;
esac

PLATFORM_PATH="$(xcrun --sdk macosx --show-sdk-platform-path 2>/dev/null || true)"
[[ -n "$PLATFORM_PATH" ]] || fail "xcrun can't resolve macosx SDK platform path. Re-run xcode-select."
ok "macOS SDK: $(xcrun --sdk macosx --show-sdk-version)"

[[ -f "$PLIST_TEMPLATE" ]] || fail "Missing $PLIST_TEMPLATE"

# Refuse to retag a version we've already published
if git -C "$ROOT_DIR" rev-parse "$TAG" >/dev/null 2>&1; then
    fail "Tag $TAG already exists. Bump the version."
fi

# Warn on dirty tree but let user proceed
if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
    printf "    ⚠ Working tree is dirty. Continue anyway? [y/N] "
    read -r REPLY
    [[ "$REPLY" =~ ^[Yy]$ ]] || exit 1
fi

ok "All prerequisites met"

# ---------------------------------------------------------------------------
# Bump version in source
# ---------------------------------------------------------------------------
step "Bumping AppConstants.swift to $VERSION"

CONSTANTS="$MACOS_DIR/Sources/K8Secret/AppConstants.swift"
sed -i '' "s/static let version = \".*\"/static let version = \"${VERSION}\"/" "$CONSTANTS"
ok "AppConstants.swift updated"

# ---------------------------------------------------------------------------
# Build release binary
# ---------------------------------------------------------------------------
step "Compiling release binary"

cd "$MACOS_DIR"
swift build -c release
# Binary location is arch-dependent (arm64 vs x86_64)
ARCH="$(uname -m)"
BINARY="$MACOS_DIR/.build/${ARCH}-apple-macosx/release/K8Secret"
[[ -x "$BINARY" ]] || fail "Built binary not found at $BINARY"
ok "Compiled: $BINARY"

# ---------------------------------------------------------------------------
# Build .app bundle from scratch
# ---------------------------------------------------------------------------
step "Building .app bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Render Info.plist from template (substitutes __VERSION__)
sed "s/__VERSION__/${VERSION}/g" "$PLIST_TEMPLATE" > "$APP_BUNDLE/Contents/Info.plist"
ok "Info.plist rendered"

# Copy binary in
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/k8secret"
chmod +x "$APP_BUNDLE/Contents/MacOS/k8secret"
ok "Binary in place"

# Copy icon if present
if [[ -f "$ICON_PATH" ]]; then
    cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    ok "Icon embedded"
else
    printf "    (no AppIcon.icns — add one at macos/release/AppIcon.icns to embed)\n"
fi

# Strip extended attributes that would trigger Gatekeeper later
xattr -cr "$APP_BUNDLE"

# Ad-hoc code sign
codesign --force --deep --sign - "$APP_BUNDLE"
ok "Ad-hoc signed"

# ---------------------------------------------------------------------------
# DMG
# ---------------------------------------------------------------------------
step "Creating DMG"

mkdir -p "$MACOS_DIR/dmg"
rm -f "$DMG_PATH"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_BUNDLE" "$STAGING/K8Secret.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "K8Secret" -fs HFS+ -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
ok "Created $DMG_PATH"

SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
SIZE_HUMAN="$(du -h "$DMG_PATH" | awk '{print $1}')"
ok "sha256: $SHA"
ok "size:   $SIZE_HUMAN"

# ---------------------------------------------------------------------------
# Git tag + commit version bump
# ---------------------------------------------------------------------------
step "Tagging $TAG"

cd "$ROOT_DIR"
git add "$CONSTANTS"
if ! git diff --cached --quiet; then
    git commit -m "release: bump to ${VERSION}"
    ok "Committed version bump"
fi
git tag "$TAG"
ok "Tag $TAG created"

# ---------------------------------------------------------------------------
# Create GitHub release
# ---------------------------------------------------------------------------
step "Creating GitHub release"

gh release create "$TAG" "$DMG_PATH" \
    --title "K8Secret ${VERSION}" \
    --notes "${NOTES}

**sha256:** \`${SHA}\`
**size:**   ${SIZE_HUMAN}
**macOS:**  14.0+

### Install

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/jai-bhardwaj/k8secret/main/release/install.sh | bash
\`\`\`

Or download the DMG directly above. The app is ad-hoc signed — the installer strips the quarantine bit so Gatekeeper won't prompt." \
    >/dev/null

ok "Release v${VERSION} published"

# ---------------------------------------------------------------------------
# Update root release/latest.json so the installer + in-app updater see it
# ---------------------------------------------------------------------------
step "Updating release manifest"

mkdir -p "$RELEASE_DIR"
TODAY="$(date +%Y-%m-%d)"
DMG_URL="https://github.com/jai-bhardwaj/k8secret/releases/download/${TAG}/$(basename "$DMG_PATH")"
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
git commit -m "release: ${VERSION} manifest" >/dev/null
ok "Manifest committed"

# ---------------------------------------------------------------------------
# Push everything
# ---------------------------------------------------------------------------
step "Pushing to origin"
git push >/dev/null
git push --tags >/dev/null
ok "Pushed commits + tag"

printf "\n✓ K8Secret v${VERSION} live.\n"
printf "  Release: https://github.com/jai-bhardwaj/k8secret/releases/tag/${TAG}\n"
printf "  DMG:     %s\n" "$DMG_URL"
printf "  Try it:  curl -fsSL https://raw.githubusercontent.com/jai-bhardwaj/k8secret/main/release/install.sh | bash\n"
