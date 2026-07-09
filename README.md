<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/brand/verdant/logo-cream.png">
  <img src="assets/lewis-it-logo.png" alt="Lewis IT Consulting" width="300">
</picture>

# LewisWhisper

**Fully-local voice dictation for macOS.** Hold a key, speak, release — your words land in any app as clean, punctuated text. No cloud, no account, no subscription.

[![Latest release](https://img.shields.io/github/v/release/lewisitconsulting1/whisp?color=D9B670&label=release)](https://github.com/lewisitconsulting1/whisp/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20·%20Apple%20Silicon-101D15)](https://github.com/lewisitconsulting1/whisp/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-2A4232)](LICENSE)
[![Signed & Notarized](https://img.shields.io/badge/app-signed%20%26%20notarized-7FB984)](https://github.com/lewisitconsulting1/whisp/releases/latest)

*Created by Chadwick Lewis · Lewis IT Consulting*

</div>

---

## Why

[Wispr Flow](https://wisprflow.ai/) proved that dictation + AI cleanup beats typing — but it's cloud-only: your voice leaves your machine, and it stops working when their servers do. LewisWhisper replicates the experience entirely on your Mac:

- **Speech-to-text on the Neural Engine** — NVIDIA Parakeet TDT 0.6B via CoreML ([FluidAudio](https://github.com/FluidInference/FluidAudio)), ~0.1 s per utterance
- **Cleanup on a local LLM** — filler removal, punctuation, and light rewriting via Ollama (`gemma3:4b` by default)
- **Sub-second end-to-end** — a typical dictation pastes in well under a second; a 13-second ramble lands in ~1.1 s, matching Wispr Flow's cloud latency offline

## Features

| | |
|---|---|
| 🎙 **Push-to-talk anywhere** | Hold **right Option**, speak, release — text pastes into whatever app has focus. Quick-tap for hands-free capture that auto-stops on silence. |
| 🧹 **Four cleanup levels** | Off (verbatim) · Light (fillers + punctuation) · Medium (clarity) · High (rewrite for brevity) |
| 📖 **Self-teaching dictionary** | Names and jargon you dictate repeatedly are learned automatically; misheard terms ("PreaWin") are corrected to your spelling ("Priya Nguyen") |
| 🪄 **Context awareness** | The cleanup model knows which app you're in — casual in Messages/Slack, professional in Mail/Word, customizable per app |
| 🔌 **Pluggable cleanup backend** | Local Ollama (default, free) · your own Ollama/LM Studio server (e.g. an office Mac mini) · or bring an API key: OpenAI, Anthropic, OpenRouter, Perplexity, Kimi. Keys live in the macOS Keychain. |
| 🔒 **Private by default** | Audio and speech-to-text never leave the Mac. Only if you *choose* a cloud cleanup provider does transcript text go out — the UI says so plainly. |
| ⚙️ **Native & lightweight** | One Swift menu-bar app, signed and notarized. No Electron, no daemons, no telemetry. |

## Install

**[Download the latest release](https://github.com/lewisitconsulting1/whisp/releases/latest)**, unzip, then:

1. Drag **`LewisWhisper.app`** to Applications and open it — the app is **notarized**, so it opens with no Gatekeeper warning.
2. For the default local cleanup, install [Ollama](https://ollama.com) and run `ollama pull gemma3:4b`. *Or* skip that and point the app at a server/cloud key in Settings → Cleanup AI.
3. Grant the three permissions the ⚠️ menu icon asks for (Microphone, Input Monitoring, Accessibility), quit & reopen once, and let the first launch fetch the speech models (~2.5 GB, one time).

> The bundled `setup.command` automates the Ollama step, but **modern macOS blocks double-clicking unsigned scripts** (a shell script can't be notarized — only the app can). Run it from Terminal with `bash <path-to-setup.command>` if you want it, or just do step 2 yourself. Full walkthrough: the bundled **Setup Guide PDF** or the one-page [Quick Install](docs/quick-install.html).

> **Requirements:** Apple Silicon (M1 or newer), macOS 14+, ~6 GB disk for models. Internet needed for setup only.

## How it works

```
hold ⌥ ──▶ AVAudioEngine (16 kHz) ──▶ Parakeet TDT v3 (CoreML, Neural Engine)
                                              │  ~0.1 s
                                              ▼
paste ◀── pasteboard + ⌘V ◀── local LLM cleanup (Ollama /api/chat) ── dictionary
  ▲                                           │  + app context & tone
  └── raw transcript fallback ◀── on any error/timeout: you never lose words
```

Measured on an M4 Pro (details in [BENCHMARKS.md](BENCHMARKS.md)):

| | STT | LLM cleanup | Total |
|---|---|---|---|
| 13 s rambling utterance | 0.11 s | 1.0 s | **1.11 s** |
| Typical short dictation | ~0.1 s | ~0.4 s | **~0.5 s** |

## Repository layout

| Path | What |
|---|---|
| [swift/](swift/) | **The app** — SPM executable, builds with Xcode CLT alone (`swift build -c release`) |
| [prototype/](prototype/) | Python proof-of-concept of the same pipeline (Phase 0) |
| [bench/](bench/) | STT + LLM benchmark scripts, test audio, raw results |
| [RESEARCH.md](RESEARCH.md) | Fact-checked research: how Wispr Flow works, the local design space |
| [BENCHMARKS.md](BENCHMARKS.md) | Measured engine/model comparisons |
| [docs/](docs/) | Setup guide, quick-install one-pager, design specs & plans |

## Build from source

```bash
git clone https://github.com/lewisitconsulting1/whisp.git
cd whisp/swift
swift build -c release      # Xcode Command Line Tools only — no full Xcode
swift test                  # 13 unit tests (providers, keychain, API dialects)
.build/release/LewisWhisper
```

`scripts/package-app.sh` assembles, signs, and (with a Developer ID + notary profile) notarizes `dist/LewisWhisper.app`.

## Roadmap

- [x] Phase 0 — research, benchmarks, Python prototype
- [x] Phase 1 — native Swift menu-bar app
- [x] Phase 2 — .app bundle + signing, first-launch permission UX, MIT license
- [x] Phase 3 — cleanup intensity levels, personal dictionary, context awareness
- [x] Phase 4 — hands-free tap-to-record with silence auto-stop
- [x] Phase 5 — auto-learned dictionary, per-app tone presets
- [x] Phase 6 — settings window, sound feedback
- [x] Phase 7 — pluggable cleanup backends (remote Ollama/LM Studio, cloud APIs), Keychain keys
- [ ] Later — Whisper engine slot (accuracy-first alternative)

## Credits

Built by **Chadwick Lewis** ([Lewis IT Consulting](https://github.com/lewisitconsulting1)) with research-first engineering: the design was reverse-engineered from public sources and benchmarked locally before a line of Swift was written. Standing on the shoulders of [FluidAudio](https://github.com/FluidInference/FluidAudio), [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), [Ollama](https://ollama.com), and prior art from [Parakey](https://github.com/rcourtman/parakey) and [VoiceInk](https://github.com/beingpax/VoiceInk).

MIT licensed — see [LICENSE](LICENSE).
