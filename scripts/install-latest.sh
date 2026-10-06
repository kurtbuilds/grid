#!/bin/bash
# Installs the latest Grid release into /Applications. On any Mac, no checkout needed:
#   curl -fsSL https://raw.githubusercontent.com/kurtbuilds/grid/master/scripts/install-latest.sh | bash
set -euo pipefail
REPO="${1:-kurtbuilds/grid}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "→ Downloading the latest Grid release from ${REPO}…"
curl -fsSL -o "$WORK/Grid.zip" "https://github.com/$REPO/releases/latest/download/Grid.zip"
ditto -x -k "$WORK/Grid.zip" "$WORK"
codesign --verify --strict "$WORK/Grid.app"

pkill -x Grid 2>/dev/null && sleep 0.5 || true
rm -rf /Applications/Grid.app
ditto "$WORK/Grid.app" /Applications/Grid.app
# Builds are signed but not notarized. curl doesn't quarantine downloads, but clear the flag
# anyway so Gatekeeper never blocks the app.
xattr -dr com.apple.quarantine /Applications/Grid.app 2>/dev/null || true
open /Applications/Grid.app
echo "✓ Installed Grid $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Grid.app/Contents/Info.plist)"
