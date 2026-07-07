#!/bin/bash
# Build LewisWhisper and assemble a signed .app bundle at dist/LewisWhisper.app.
# Uses a "Developer ID Application" cert if one exists, else ad-hoc signs
# (fine for personal use; ad-hoc TCC grants can reset when the binary changes).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "building release..."
swift build -c release --package-path swift

APP="dist/LewisWhisper.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp swift/.build/release/LewisWhisper "$APP/Contents/MacOS/LewisWhisper"
cp swift/Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"

CERT=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application:/ {print $2; exit}' || true)
if [ -n "${CERT:-}" ]; then
    echo "signing with: $CERT"
    codesign --force --deep --sign "$CERT" --options runtime \
        --entitlements swift/entitlements.plist --timestamp "$APP"
else
    echo "no Developer ID cert found — ad-hoc signing"
    codesign --force --deep --sign - --entitlements swift/entitlements.plist "$APP"
fi

codesign --verify --deep --strict "$APP"
echo "--- embedded entitlements ---"
codesign -d --entitlements - "$APP" 2>/dev/null
echo
echo "done: $APP  (install: cp -R $APP /Applications/)"
