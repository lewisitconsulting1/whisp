#!/bin/bash
# Build LewisWisper and assemble a signed .app bundle at dist/LewisWisper.app.
# Uses a "Developer ID Application" cert if one exists, else ad-hoc signs
# (fine for personal use; ad-hoc TCC grants can reset when the binary changes).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "building release..."
swift build -c release --package-path swift

APP="dist/LewisWisper.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp swift/.build/release/LewisWisper "$APP/Contents/MacOS/LewisWisper"
cp swift/Info.plist "$APP/Contents/Info.plist"

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
