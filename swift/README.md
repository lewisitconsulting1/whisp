# LewisWisper — native Swift app (Phase 1)

Menu-bar push-to-talk dictation, fully local: **hold RIGHT OPTION → speak → release → cleaned text pastes into the focused app.**

Pipeline: CGEvent tap hotkey → AVAudioEngine (16 kHz mono) → Parakeet TDT 0.6B v3 on the Neural Engine (FluidAudio) → gemma3:4b cleanup via Ollama → pasteboard + synthetic Cmd+V.

## Build & run

Requires only Xcode Command Line Tools (no full Xcode):

```bash
cd swift
swift build -c release
.build/release/LewisWisper                    # default: gemma3:4b, light cleanup
.build/release/LewisWisper --cleanup off      # raw transcript, fastest
.build/release/LewisWisper --model llama3.1:latest
.build/release/LewisWisper --hotkey cmd_r     # alt_r (default) | cmd_r | ctrl_r
```

A 🎙 icon appears in the menu bar ("…" while the model loads, 🔴 recording, ⏳ transcribing). Quit from the menu or Ctrl+C in the terminal.

Permissions: same three as the Python prototype (Microphone, Input Monitoring, Accessibility), attributed to the terminal app you launch from — if you already granted them for the prototype, no new prompts.

First-ever launch downloads the Parakeet CoreML models from HuggingFace (~2.5 GB, cached at `~/Library/Application Support/FluidAudio/Models/`) and compiles them for the Neural Engine — that one-time step can take many minutes. Every later launch is seconds.

## Headless pipeline check

```bash
.build/release/LewisWisper --selftest ../bench/audio/fillers.wav
```

Runs STT + cleanup on a WAV and exits — no permissions needed. Measured on this M4 Pro: **stt 0.11 s, llm 1.00 s, total 1.11 s** for 13.3 s of filler-laden speech.

## Design notes (patterns adopted from Parakey, MIT)

- Hotkey press/release is tracked by the key's own down-state, not the modifier flag mask (left+right Option share `.maskAlternate`); tap handlers dispatch async because >1 s of work in a tap callback gets the tap disabled by macOS; tap re-enables itself after `tapDisabledByTimeout`.
- Paste posts real Cmd down/up key events around the V (flag-only synthetic shortcuts are unreliable after sleep/wake). Unlike Parakey we restore the previous clipboard contents after 0.4 s.
- ASR model loads **before** the audio engine and hotkey start (reversed order can hang the first-launch CoreML compile). A silent warmup transcription at startup absorbs the ANE graph compile so the first real dictation is fast.
- The ANE doesn't tolerate concurrent inference on one compiled graph — the app-level `busy` flag serializes dictations.
- The AVAudioConverter input block returns `.noDataNow` after handing over each buffer (returning `.endOfStream` would put a reused converter into a terminal state).

## .app bundle (Phase 2)

```bash
../scripts/package-app.sh          # builds + assembles + signs dist/LewisWisper.app
cp -R ../dist/LewisWisper.app /Applications/
```

Signs with a "Developer ID Application" cert if you have one, else ad-hoc (personal use; ad-hoc TCC grants can reset when the binary changes — re-grant after rebuilds). The bundled app carries the mic entitlements macOS 26+ requires and its own permission UX: on first launch it fires the three system permission prompts, shows ⚠️ in the menu bar with "Open … Settings" shortcuts for anything still missing, and starts automatically once everything is granted. Permissions attach to `com.lewisitconsulting.lewiswisper` itself, not your terminal.

## Not yet done (Phase 3)

Cleanup intensity levels beyond light, personal dictionary (fixes proper-noun spellings and gemma's occasional greeting/hedge-word drops), near-cursor context awareness, settings UI, custom menu-bar icon.
