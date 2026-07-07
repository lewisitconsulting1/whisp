# LewisWhisper — native Swift app (Phase 1)

Menu-bar push-to-talk dictation, fully local: **hold RIGHT OPTION → speak → release → cleaned text pastes into the focused app.** Or **quick-tap** for hands-free recording that ends on the next tap or ~1 s of silence.

Pipeline: CGEvent tap hotkey → AVAudioEngine (16 kHz mono) → Parakeet TDT 0.6B v3 on the Neural Engine (FluidAudio) → gemma3:4b cleanup via Ollama → pasteboard + synthetic Cmd+V.

## Build & run

Requires only Xcode Command Line Tools (no full Xcode):

```bash
cd swift
swift build -c release
.build/release/LewisWhisper                    # default: gemma3:4b, light cleanup
.build/release/LewisWhisper --cleanup off      # raw transcript, fastest
.build/release/LewisWhisper --model llama3.1:latest
.build/release/LewisWhisper --hotkey cmd_r     # alt_r (default) | cmd_r | ctrl_r
```

A 🎙 icon appears in the menu bar ("…" while the model loads, 🔴 recording, ⏳ transcribing). Quit from the menu or Ctrl+C in the terminal.

Permissions: same three as the Python prototype (Microphone, Input Monitoring, Accessibility), attributed to the terminal app you launch from — if you already granted them for the prototype, no new prompts.

First-ever launch downloads the Parakeet CoreML models from HuggingFace (~2.5 GB, cached at `~/Library/Application Support/FluidAudio/Models/`) and compiles them for the Neural Engine — that one-time step can take many minutes. Every later launch is seconds.

## Headless pipeline check

```bash
.build/release/LewisWhisper --selftest ../bench/audio/fillers.wav
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
../scripts/package-app.sh          # builds + assembles + signs dist/LewisWhisper.app
cp -R ../dist/LewisWhisper.app /Applications/
```

Signs with a "Developer ID Application" cert if you have one, else ad-hoc (personal use; ad-hoc TCC grants can reset when the binary changes — re-grant after rebuilds). The bundled app carries the mic entitlements macOS 26+ requires and its own permission UX: on first launch it fires the three system permission prompts, shows ⚠️ in the menu bar with "Open … Settings" shortcuts for anything still missing, and starts automatically once everything is granted. Permissions attach to `com.lewisitconsulting.lewiswhisper` itself, not your terminal.

## Phase 3 features

- **Cleanup levels** (menu › Cleanup, or `--cleanup off|light|medium|high`): Off = verbatim; Light = fillers + punctuation, nothing else; Medium = light restructuring for clarity; High = rewrite for brevity. Persisted across launches.
- **Personal dictionary** (menu › Edit Personal Dictionary…): one term per line at `~/Library/Application Support/LewisWhisper/dictionary.txt`; misheard words phonetically matching an entry are replaced with the exact spelling ("PreaWin" → "Priya Nguyen"). Add mishearing hints in parentheses for stubborn cases: `Ollama (often misheard as Alema)`. Reloaded on every dictation — edits apply immediately.
- **Context awareness** (menu › Context Awareness, on by default): the frontmost app's name and up to 300 chars of the focused field's text (via Accessibility; secure fields excluded) are given to the cleanup model for spelling/tone reference.

## Not yet done

Auto-learned dictionary from corrections, per-app tone presets, settings UI, Whisper engine slot.
