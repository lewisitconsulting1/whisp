#!/bin/bash
# Build LewisWhisper and assemble a signed .app bundle at dist/LewisWhisper.app.
# Uses a "Developer ID Application" cert if one exists, else ad-hoc signs
# (fine for personal use; ad-hoc TCC grants can reset when the binary changes).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "building release..."
swift build -c release --package-path swift

# assemble + sign in /tmp: ~/Documents is iCloud-synced, and File Provider
# tags bundle files between cp and codesign, which codesign rejects as detritus
STAGE=$(mktemp -d /tmp/lewiswhisper-pkg.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/LewisWhisper.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -X swift/.build/release/LewisWhisper "$APP/Contents/MacOS/LewisWhisper"
cp -X swift/Info.plist "$APP/Contents/Info.plist"
cp -X assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -X assets/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"
# strip Finder info/resource-fork xattrs — codesign rejects them ("detritus")
xattr -cr "$APP"

NOTARY_PROFILE="lewiswhisper-notary"
CERT=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application:/ {print $2; exit}' || true)
if [ -n "${CERT:-}" ]; then
    echo "signing with: $CERT"
    codesign --force --deep --sign "$CERT" --options runtime \
        --entitlements swift/entitlements.plist --timestamp "$APP"

    # notarize + staple if credentials are stored
    # (one-time setup: xcrun notarytool store-credentials lewiswhisper-notary \
    #    --apple-id <apple-id-email> --team-id WFJF94UR9E --password <app-specific-password>)
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "notarizing (Apple usually takes 1-5 minutes)..."
        NOTARY_TMP=$(mktemp -d)
        ditto -c -k --keepParent "$APP" "$NOTARY_TMP/LewisWhisper.zip"
        xcrun notarytool submit "$NOTARY_TMP/LewisWhisper.zip" \
            --keychain-profile "$NOTARY_PROFILE" --wait
        rm -rf "$NOTARY_TMP"
        xcrun stapler staple "$APP"
        xcrun stapler validate "$APP"
        echo "notarized + stapled — opens on any Mac with no warnings"
    else
        echo "notarization skipped — no '$NOTARY_PROFILE' keychain profile"
    fi
else
    echo "no Developer ID cert found — ad-hoc signing"
    codesign --force --deep --sign - --entitlements swift/entitlements.plist "$APP"
fi

# Gatekeeper/Finder can re-tag the bundle between steps; xattrs aren't part
# of the code seal, so stripping again before strict verify is safe
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"
echo "--- embedded entitlements ---"
codesign -d --entitlements - "$APP" 2>/dev/null

rm -rf dist/LewisWhisper.app
mkdir -p dist
mv "$APP" dist/LewisWhisper.app
echo
echo "done: dist/LewisWhisper.app  (install: cp -R dist/LewisWhisper.app /Applications/)"
