#!/bin/zsh
# Builds Clipi and creates build/Clipi.app.
#
#   ./build.sh           build only
#   ./build.sh run       build and launch from build/
#   ./build.sh install   build, copy to /Applications and launch
#
# Signing: with "Clipi Local Signing" in the keychain (scripts/make-signing-cert.sh) local builds
# keep one identity, so macOS keeps Clipi's Accessibility (Quick Paste) and Full Disk Access
# ("Keep Floating Thumbnail") across rebuilds. Without it they're signed ad-hoc: a new identity
# every build, so "run" and "install" reset Accessibility and Clipi asks for it again. With a stable signing
# certificate (SIGN_IDENTITY="Certificate name" ./build.sh install) the permission survives
# rebuilds. A real identity also enables the hardened runtime and a secure timestamp, both
# required for notarization.
#
# Optional environment variables (used by the GitHub Actions release workflow):
#   ARCHS="arm64 x86_64"   build a universal binary (needs Xcode, not just the Command Line Tools)
#   VERSION=1.2.0          CFBundleShortVersionString
#   BUILD_NUMBER=42        CFBundleVersion
set -euo pipefail
cd "${0:A:h}"

APP_NAME=Clipi
BUNDLE_ID=com.davideleone.Clipi
LOCAL_IDENTITY="Clipi Local Signing"
if [[ -z "${SIGN_IDENTITY:-}" ]] && security find-certificate -c "$LOCAL_IDENTITY" >/dev/null 2>&1; then
    SIGN_IDENTITY="$LOCAL_IDENTITY"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/$APP_NAME.app"

swift_args=(-c release)
for arch in ${=ARCHS:-}; do
    swift_args+=(--arch "$arch")
done
swift build "${swift_args[@]}"
BIN_DIR="$(swift build "${swift_args[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# App icon: every size macOS needs, scaled down from the 1024×1024 Resources/icon.png.
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/icon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/icon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "${iconset:h}"
if [[ -n "${VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

codesign_args=(--force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID")
if [[ "$SIGN_IDENTITY" != "-" && "$SIGN_IDENTITY" != "$LOCAL_IDENTITY" ]]; then
    codesign_args+=(--options runtime --timestamp)  # Developer ID: ready for notarization
fi
codesign "${codesign_args[@]}" "$APP"
echo "✓ $APP"

launch() {
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 && sleep 1 || true
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        # A new ad-hoc build has a new identity: clear the stale Accessibility entry so Clipi can ask again.
        tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi
    open "$1"
}

case "${1:-}" in
    run)
        launch "$APP"
        ;;
    install)
        rm -rf "/Applications/$APP_NAME.app"
        ditto "$APP" "/Applications/$APP_NAME.app"
        echo "✓ /Applications/$APP_NAME.app"
        launch "/Applications/$APP_NAME.app"
        ;;
    "") ;;
    *)
        echo "Usage: $0 [run|install]" >&2
        exit 1
        ;;
esac
