# LewisWhisper

A fully-local [Wispr Flow](https://wisprflow.ai/) clone for macOS (project codename `whisp`): hold a hotkey, speak, release — your words land in the focused app as clean, punctuated text. Speech-to-text runs on the Neural Engine (Parakeet TDT 0.6B via FluidAudio), transcript cleanup runs on a local LLM via Ollama. No cloud, no network, no subscription.

## Layout

| Path | What |
|---|---|
| [swift/](swift/) | **The app** — native Swift menu-bar push-to-talk dictation (Phase 1) |
| [prototype/](prototype/) | Python proof-of-concept of the same pipeline (Phase 0) |
| [bench/](bench/) | STT + LLM benchmark scripts, test audio, raw results |
| [RESEARCH.md](RESEARCH.md) | Fact-checked research: how Wispr Flow works, design space, build plan |
| [BENCHMARKS.md](BENCHMARKS.md) | Measured engine/model comparisons on this M4 Pro |

## Quick start

```bash
cd swift && swift build -c release && .build/release/LewisWhisper
```

Hold **right Option** to dictate. See [swift/README.md](swift/README.md) for permissions and options.

## Measured performance (M4 Pro, 48 GB)

| | STT | LLM cleanup | Total |
|---|---|---|---|
| 13 s rambling utterance | 0.11 s | 1.0 s | **1.11 s** |
| Typical short dictation (est.) | ~0.1 s | ~0.4 s | **~0.5 s** |

Wispr Flow's cloud pipeline targets 700 ms p99 — whisp matches it offline.

## Install as an app

```bash
scripts/package-app.sh && cp -R dist/LewisWhisper.app /Applications/
```

## Roadmap

- [x] Phase 0 — research, benchmarks, Python prototype
- [x] Phase 1 — native Swift menu-bar app
- [x] Phase 2 — .app bundle + signing, first-launch permission UX, MIT license
- [x] Phase 3 — cleanup intensity levels (Off/Light/Medium/High), personal dictionary, context awareness
- [x] Phase 4 — hands-free tap-to-record with silence auto-stop
- [x] Phase 5 — auto-learned dictionary, per-app tone presets
- [x] Phase 6 — settings window (hotkey/model pickers, silence delay), sound feedback
- [x] Phase 7 — pluggable cleanup backends: remote Ollama/LM Studio servers + cloud APIs (OpenAI, Anthropic, OpenRouter, Perplexity, Kimi), Keychain-stored keys
- [ ] Later — Whisper engine slot (accuracy-first alternative)
