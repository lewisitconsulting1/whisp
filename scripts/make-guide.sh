#!/bin/bash
# Render docs/setup-guide.html to a PDF via headless Chrome.
# Usage: scripts/make-guide.sh [output.pdf]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist/LewisWhisper Setup Guide.pdf}"
mkdir -p "$(dirname "$OUT")"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --headless --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$OUT" \
    "file://$(pwd)/docs/setup-guide.html" 2>/dev/null
echo "wrote $OUT"
