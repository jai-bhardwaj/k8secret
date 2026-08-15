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

# A usable macOS SDK is required. Full Xcode is preferred, but the Command
# Line Tools build this Swift package fine too (verified: swift build produces
# a working binary), so accept either as long as the SDK version resolves.
XCODE_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
case "$XCODE_DEV_DIR" in
    *Xcode.app/Contents/Developer*) ok "Xcode active at $XCODE_DEV_DIR" ;;
    *) printf "    ⚠ Full Xcode not active (using: %s). Building with Command Line Tools.\n" "${XCODE_DEV_DIR:-none}" ;;
esac

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
[[ -n "$SDK_VERSION" ]] || fail "xcrun can't resolve the macOS SDK. Install Xcode, or run: xcode-select --install"
ok "macOS SDK: $SDK_VERSION"

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
step "Compiling universal release binary"

cd "$MACOS_DIR"

# Build both slices and lipo them together. Building only the host architecture
# shipped an arm64-only DMG that simply would not launch on an Intel Mac — and
# nothing downstream noticed, because the release machine could always run it.
UNIVERSAL_DIR="$MACOS_DIR/.build/universal"
mkdir -p "$UNIVERSAL_DIR"
BINARY="$UNIVERSAL_DIR/K8Secret"

for SLICE in arm64 x86_64; do
    printf "    building %s slice...\n" "$SLICE"
    swift build -c release --arch "$SLICE"
    SLICE_BIN="$MACOS_DIR/.build/${SLICE}-apple-macosx/release/K8Secret"
    [[ -x "$SLICE_BIN" ]] || fail "Missing $SLICE build at $SLICE_BIN"
done

lipo -create \
    "$MACOS_DIR/.build/arm64-apple-macosx/release/K8Secret" \
    "$MACOS_DIR/.build/x86_64-apple-macosx/release/K8Secret" \
    -output "$BINARY"

# Assert both slices actually made it in, rather than trusting lipo silently.
for SLICE in arm64 x86_64; do
    lipo -info "$BINARY" | grep -q "$SLICE" || fail "Universal binary is missing the $SLICE slice"
done
ok "Universal binary: $(lipo -info "$BINARY" | sed 's/.*are: //')"

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

# ---------------------------------------------------------------------------
# Code signing
#
# Set these to produce a notarized, Gatekeeper-clean build:
#
#   export K8SECRET_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   export K8SECRET_NOTARY_PROFILE="k8secret"     # from: xcrun notarytool store-credentials
#
# Without them the build falls back to ad-hoc signing, which still works but
# requires the installer to strip quarantine — see the Install section of the
# README for what that costs the user.
# ---------------------------------------------------------------------------
SIGN_IDENTITY="${K8SECRET_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${K8SECRET_NOTARY_PROFILE:-}"

if [[ -n "$SIGN_IDENTITY" ]]; then
    # Hardened runtime is a prerequisite for notarization. The app shells out to
    # kubectl and to credential plugins, which the runtime permits — those are
    # separate processes with their own signatures, not injected libraries.
    codesign --force --timestamp --options runtime \
        --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    codesign --verify --strict --verbose=2 "$APP_BUNDLE" 2>&1 | sed 's/^/    /'
    ok "Signed with Developer ID (hardened runtime)"
else
    codesign --force --sign - "$APP_BUNDLE"
    printf "    ⚠ Ad-hoc signed — not notarizable.\n"
    printf "      Set K8SECRET_SIGN_IDENTITY + K8SECRET_NOTARY_PROFILE to ship a\n"
    printf "      Gatekeeper-clean build that doesn't need the quarantine strip.\n"
fi

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

# ---------------------------------------------------------------------------
# Notarize + staple
#
# Stapling attaches the notarization ticket to the DMG so it validates offline.
# The checksum is computed *after* this step — stapling rewrites the file.
# ---------------------------------------------------------------------------
if [[ -n "$SIGN_IDENTITY" && -n "$NOTARY_PROFILE" ]]; then
    step "Notarizing"
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$DMG_PATH"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait \
        || fail "Notarization failed. Check: xcrun notarytool log --keychain-profile $NOTARY_PROFILE <submission-id>"
    xcrun stapler staple "$DMG_PATH" || fail "Stapling failed"
    xcrun stapler validate "$DMG_PATH" >/dev/null || fail "Stapled ticket did not validate"
    ok "Notarized and stapled"
elif [[ -n "$SIGN_IDENTITY" ]]; then
    printf "    ⚠ Signed but not notarized (K8SECRET_NOTARY_PROFILE unset)\n"
fi

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

# Push commits + the tag BEFORE creating the GitHub release.
# `gh release create` refuses to attach an asset to a tag that doesn't
# yet exist on the remote — and creating it via --target would point
# at HEAD instead of our explicit version-bump commit. Pushing first is
# the cheapest correct fix.
git push >/dev/null
git push origin "$TAG" >/dev/null
ok "Pushed commits + tag $TAG"

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
# sha256 is what the installer and the in-app updater verify the download against;
# without it in the manifest both refuse to install.
jq -n \
    --arg version "$VERSION" \
    --arg url "$DMG_URL" \
    --arg notes "$NOTES" \
    --arg date "$TODAY" \
    --arg sha256 "$SHA" \
    '{
        version: $version,
        url: $url,
        notes: $notes,
        minOS: "14.0",
        date: $date,
        sha256: $sha256
    }' > "$RELEASE_DIR/latest.json"

git add "$RELEASE_DIR/latest.json"
git commit -m "release: ${VERSION} manifest" >/dev/null
ok "Manifest committed"

# ---------------------------------------------------------------------------
# Push the manifest commit
# ---------------------------------------------------------------------------
step "Pushing manifest"
git push >/dev/null
ok "Manifest live on main"

printf "\n✓ K8Secret v${VERSION} live.\n"
printf "  Release: https://github.com/jai-bhardwaj/k8secret/releases/tag/${TAG}\n"
printf "  DMG:     %s\n" "$DMG_URL"
printf "  Try it:  curl -fsSL https://raw.githubusercontent.com/jai-bhardwaj/k8secret/main/release/install.sh | bash\n"
