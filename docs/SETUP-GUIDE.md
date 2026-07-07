# LewisWhisper — Setup Guide

**Local voice dictation for your Mac.** Hold a key, speak, release — your words appear in whatever app you're typing in, cleaned up into proper sentences. Everything runs on your Mac: no cloud, no account, no subscription, and your voice never leaves the machine.

---

## What you need

- A Mac with an **Apple Silicon** chip (M1 or newer — 2020 and later)
- **macOS 14** (Sonoma) or newer
- About **6 GB of free disk space** (AI models)
- Internet connection **for setup only** (model downloads); after that it works fully offline

---

## Install (the easy way)

1. Unzip the folder you received.
2. Double-click **`setup.command`**.
   - If macOS says it can't verify the developer: **right-click → Open → Open**.
3. Follow the prompts. The script installs the app, installs/starts **Ollama** (the free program that runs the cleanup AI), and downloads the AI model (~3.3 GB, one time).
4. When LewisWhisper launches, a **⚠️ icon** appears in the menu bar (top-right of your screen, near the clock). Grant the three permissions it asks for:
   - **Microphone** — click *Allow* on the popup
   - **Input Monitoring** — System Settings opens; turn the **LewisWhisper** switch ON
   - **Accessibility** — same, turn the switch ON
5. **Quit the app** (click the ⚠️/soundwave icon → Quit LewisWhisper) and **open it once more** from Applications. macOS applies some permissions only to a freshly started app.
6. First launch downloads the speech-recognition models (~2.5 GB). The icon shows **…** while loading — give it a few minutes the first time. When you see the **soundwave icon**, you're ready.

## Install (manual, if you prefer)

1. Drag **LewisWhisper.app** into your **Applications** folder.
2. Open **Terminal** and run: `xattr -cr /Applications/LewisWhisper.app` (clears the "unverified developer" block).
3. Install Ollama from **ollama.com/download**, open it once, then run in Terminal: `ollama pull gemma3:4b`
4. Open LewisWhisper and continue from step 4 above.

<div style="page-break-before: always;"></div>

## Using it

**Hold the RIGHT OPTION (⌥) key, speak, let go.** Your words paste into whatever app has the cursor — Mail, Messages, Word, Slack, anywhere. A 5-second sentence lands in about a second.

The menu bar icon shows what's happening: **soundwave** = ready · 🔴 = recording · ⏳ = transcribing · **…** = loading · ⚠️ = needs permissions.

Click the icon for options:

| Menu item | What it does |
|---|---|
| **Cleanup** | How much the AI tidies your speech. **Off** = your exact words. **Light** = removes "um"s, fixes punctuation (recommended). **Medium** = also smooths clumsy sentences. **High** = rewrites for brevity. |
| **Context Awareness** | Lets the cleanup AI see which app you're in (and nearby text) so tone and spelling fit. Passwords are never read. |
| **Edit Personal Dictionary…** | A text file of names and jargon it should always spell right — one per line (e.g. your name, company, product names). For stubborn words, add a hint: `Ollama (often misheard as Alema)`. Changes apply instantly. |

**Tip:** add the names of people and products you say often to the Personal Dictionary right away — it's the single biggest accuracy upgrade.

---

## Troubleshooting

**"LewisWhisper can't be opened / is damaged"** — the app isn't in Apple's registry (it's homemade, not from the App Store). Right-click the app → **Open** → **Open**, or run `xattr -cr /Applications/LewisWhisper.app` in Terminal.

**⚠️ icon won't go away after granting permissions** — quit the app (menu → Quit) and reopen it. If it *still* shows ⚠️: open the System Settings pane it names, **remove** the LewisWhisper entry with the **−** button, then reopen the app and grant fresh when it asks. (macOS ties permissions to the exact copy of the app; a stale entry looks ON but does nothing.)

**Dictation pastes my exact words with the "um"s left in** — the cleanup AI isn't reachable. Make sure **Ollama** is running (menu bar llama icon, or just open the Ollama app) and the model is installed: `ollama pull gemma3:4b`. Dictation itself keeps working either way — you never lose words.

**Nothing happens when I hold right Option** — check the icon isn't ⚠️, and make sure you're using the option key on the **right** side of the space bar.

**First dictation after a long break is slow** — the cleanup model reloads after ~30 min idle. One slow response, then it's fast again.

---

## Privacy

Your audio is processed entirely on this Mac: speech recognition runs on the Apple Neural Engine, and text cleanup runs in Ollama locally. Nothing is uploaded, logged, or shared. The app needs internet exactly once — to download its AI models during setup.

*LewisWhisper · Lewis IT Consulting · MIT licensed · github.com/lewisitconsulting1/whisp*
