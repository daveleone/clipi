#!/bin/sh
# Downloads the latest Clipi release and installs it, without Gatekeeper prompts:
# files downloaded with curl don't get the quarantine flag that browsers add.
#
#   curl -fsSL https://raw.githubusercontent.com/daveleone/clipi/main/scripts/install.sh | sh
set -eu

URL="https://github.com/daveleone/clipi/releases/latest/download/Clipi.zip"
BUNDLE_ID=com.davideleone.Clipi

if [ -w /Applications ]; then
    DEST=/Applications
else
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi
APP="$DEST/Clipi.app"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Clipi…"
curl -fL --progress-bar "$URL" -o "$TMP/Clipi.zip"
ditto -x -k "$TMP/Clipi.zip" "$TMP"

# Quit gracefully so Clipi saves its history and restores the screenshot thumbnail setting.
osascript -e 'quit app "Clipi"' >/dev/null 2>&1 && sleep 1 || true
rm -rf "$APP"
ditto "$TMP/Clipi.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# An ad-hoc signed build gets a new identity every release, so old Full Disk Access and
# Accessibility entries no longer match: clear them so they can be granted again.
if codesign -dv "$APP" 2>&1 | grep -q "Signature=adhoc"; then
    tccutil reset SystemPolicyAllFiles "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

echo "✓ Installed in $APP"
open "$APP"
