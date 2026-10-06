#!/bin/bash
# Installs the latest Grid release into /Applications. Works on any Mac where `gh` is signed in
# (the repo is private), with or without a checkout:
#   gh api repos/kurtbuilds/grid/contents/scripts/install-latest.sh -H "Accept: application/vnd.github.raw" | bash
set -euo pipefail
REPO="${1:-kurtbuilds/grid}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "→ Downloading the latest Grid release from $REPO…"
gh release download --repo "$REPO" --pattern Grid.zip --dir "$WORK"
ditto -x -k "$WORK/Grid.zip" "$WORK"
codesign --verify --strict "$WORK/Grid.app"

pkill -x Grid 2>/dev/null && sleep 0.5 || true
rm -rf /Applications/Grid.app
ditto "$WORK/Grid.app" /Applications/Grid.app
# Builds are signed but not notarized; make sure no quarantine flag makes Gatekeeper block them.
xattr -dr com.apple.quarantine /Applications/Grid.app 2>/dev/null || true
open /Applications/Grid.app
echo "✓ Installed Grid $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Grid.app/Contents/Info.plist)"
