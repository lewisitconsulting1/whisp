#!/bin/bash
# LewisWhisper setup helper (OPTIONAL — installs Ollama + the cleanup model).
# The app itself is notarized and opens fine by dragging it to Applications;
# you only need this script for the Ollama convenience.
# Modern macOS blocks double-clicking unsigned scripts. To run it, open
# Terminal and type:  bash <drag this file in>   — or install Ollama yourself
# from ollama.com and run:  ollama pull gemma3:4b
set -e
cd "$(dirname "$0")"
echo "== LewisWhisper setup =="

if [ "$(uname -m)" != "arm64" ]; then
    echo "✗ LewisWhisper requires an Apple Silicon Mac (M1 or newer)."
    exit 1
fi

if [ ! -d "LewisWhisper.app" ]; then
    echo "✗ LewisWhisper.app not found next to this script — keep them in the same folder."
    exit 1
fi

echo "Installing LewisWhisper.app to /Applications..."
rm -rf /Applications/LewisWhisper.app
cp -R "LewisWhisper.app" /Applications/
# clear the quarantine flag so Gatekeeper doesn't block the unsigned app
xattr -cr /Applications/LewisWhisper.app

if ! command -v ollama >/dev/null 2>&1 && [ ! -d /Applications/Ollama.app ]; then
    echo ""
    echo "Ollama is not installed yet. Opening the download page —"
    echo "install it, open it once, then double-click this script again."
    open "https://ollama.com/download"
    exit 0
fi

open -a Ollama 2>/dev/null || true
sleep 2
echo "Downloading the cleanup model (gemma3:4b, ~3.3 GB — one time)..."
if command -v ollama >/dev/null 2>&1; then
    ollama pull gemma3:4b || echo "! Model pull failed — open Terminal later and run: ollama pull gemma3:4b"
else
    echo "! Could not find the ollama command — open Terminal and run: ollama pull gemma3:4b"
fi

echo "Launching LewisWhisper..."
open /Applications/LewisWhisper.app
echo ""
echo "Almost done — grant the 3 permissions (the ⚠️ menu bar icon guides you):"
echo "  1. Microphone       — click Allow on the popup"
echo "  2. Input Monitoring — toggle LewisWhisper ON in System Settings"
echo "  3. Accessibility    — toggle LewisWhisper ON in System Settings"
echo "Then QUIT the app (menu bar icon > Quit LewisWhisper) and open it once more."
echo ""
echo "First launch downloads speech models (~2.5 GB); the menu bar icon shows … while loading."
echo "Ready when you see the soundwave icon: hold RIGHT OPTION, speak, release."
