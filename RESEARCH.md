# whisp — Cloning Wispr Flow as a fully-local macOS dictation app

**Research report & build plan** · 2026-07-03
Produced by a deep-research pass: 24 sources fetched, 120 claims extracted, 25 top claims adversarially verified (3-vote panels) — **25 confirmed, 0 refuted**. Confidence labels below reflect those votes.

**Target machine:** Apple M4 Pro, 48 GB RAM, macOS 27.0. Ollama (`/usr/local/bin/ollama`) and LM Studio already installed; ffmpeg present; Xcode Command Line Tools installed (clang 16) — full Xcode still needed for the Phase 1+ SwiftUI app.

---

## TL;DR

Wispr Flow is a **cloud-only** two-stage pipeline — server-side speech recognition followed by a fine-tuned Llama "transcript cleanup" model on Baseten/AWS — completing in <700 ms p99 and pasting the result into whatever app has focus. Nothing runs on-device, which is exactly the gap a local clone fills.

Every stage is replicable locally on your hardware:

| Stage | Wispr Flow (cloud) | Local equivalent | Verified performance |
|---|---|---|---|
| Hotkey + capture | hold-to-talk, system-wide | CGEventTap + AVFoundation | ~0 cost |
| Speech-to-text | cloud ASR, <200 ms | **Parakeet TDT 0.6B via FluidAudio/CoreML on the Neural Engine** | ~0.19 s/utterance on M4 (~110x real-time) |
| AI cleanup | fine-tuned Llama on Baseten, <200 ms | **gemma3:4b-class model via Ollama** (`localhost:11434`) | ~0.3–1 s (unbenchmarked locally — validate) |
| Insertion | paste into focused app | pasteboard write + synthetic Cmd+V CGEvent | ~instant (Parakey: ~100 ms key-release→pasted) |
| Network | ~200 ms | — | 0 ms (the local win) |

Realistic end-to-end target on the M4 Pro: **~100–300 ms without LLM cleanup, ~0.5–1.5 s with it** — bracketing Wispr Flow's 700 ms cloud p99, fully private.

---

## 1. How Wispr Flow actually works (all high-confidence, vendor-documented)

**Architecture.** Cloud-only two-stage pipeline: server-side ASR, then an AI cleanup step built on **fine-tuned Llama models**, with inference on Baseten's AWS infrastructure (plus OpenAI/Anthropic/Cerebras per privacy docs). There is no on-device or offline mode — Wispr's own docs state transcription "always happens in the cloud," even in Privacy Mode, and a May–June 2026 outage halted dictation entirely. *(12-0 verification vote; sources: Baseten case study quoting Wispr's CTO, wisprflow.ai, docs.wisprflow.ai)*

**Latency bar.** Full pipeline <700 ms at p99 from end-of-speech, with a published budget of <200 ms ASR + <200 ms LLM (100+ tokens in <250 ms) + ~200 ms network. Marketing throughput: ~220 wpm vs 45 wpm typing. A local clone deletes the ~200 ms network leg, so **~500 ms-class local latency matches the commercial product**. *(6-0; Baseten + Wispr engineering blog. Caveat: 700 ms is a design target with documented 2026 latency incidents; 220 wpm is a vendor figure.)*

**Feature set to replicate** *(9-0)*:
- **Hold-hotkey push-to-talk** dictation into any app, system-wide.
- **Personal dictionary** — auto-learns proper nouns from user corrections (opt-in), manual additions supported.
- **Context awareness** — reads a limited amount of text near the cursor in the focused field plus the active app identity; used for proper-noun accuracy, style matching, formatting. On by default on Mac; password fields excluded.
- **Auto Cleanup intensity**, four levels: None (verbatim) / Light (fillers + grammar) / Medium (clarity) / High (rewrites for brevity). Plus a beta "Transforms" feature (highlight text → hotkey → AI rewrite).

For a local clone, dictionary + context map to: injecting terms and near-cursor text into the STT prompt (e.g. Whisper `initial_prompt`) and/or the LLM cleanup prompt; cleanup intensity maps to a selectable system prompt.

---

## 2. macOS implementation pattern (source-code-verified, 6-0)

The proven insertion pattern — used by Parakey and local-whisper independently:

1. Write transcript to the **general pasteboard** (`NSPasteboard`).
2. Post a **synthetic Cmd+V via CGEvent**.
3. Fallback: per-key **Unicode CGEvent typing** (for apps where paste fails).

(Preserving/restoring the user's prior clipboard contents is the standard courtesy step.)

Exactly **three TCC permissions** are required:

| Permission | Why | API check |
|---|---|---|
| Microphone | recording | `AVCaptureDevice.authorizationStatus` |
| Accessibility | posting synthetic events | `AXIsProcessTrusted()` |
| Input Monitoring | observing the global hotkey | `CGPreflightListenEventAccess()` |

Hold/release hotkey detection uses a **`flagsChanged` CGEvent tap** (e.g. hold-Fn or hold-Right-Cmd), the same pattern in both reference implementations. Parakey achieves **~100 ms from key release to pasted text** with this stack.

---

## 3. Local STT engines on Apple Silicon

**Winner: NVIDIA Parakeet TDT 0.6B, converted to CoreML, run on the Apple Neural Engine via FluidAudio** (Apache-2.0 Swift SDK). In a 9-engine head-to-head on a MacBook Pro M4 24 GB (github.com/anvanvan/mac-whisper-speedtest): *(9-0)*

| Engine | Time (same test audio) |
|---|---|
| **FluidAudio CoreML (Parakeet TDT 0.6B)** | **0.19 s** (~110x real-time) |
| mlx-whisper | 1.02 s |
| whisper.cpp + CoreML | 1.23 s |
| WhisperKit | 2.22 s |
| faster-whisper | 6.96 s |

Production-proven: Parakey defaults to multilingual Parakeet TDT **v3** (25 European languages); VoiceInk uses FluidAudio for its Parakeet engine. Models hosted at `huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml`.

**Alternatives:**
- **WhisperKit** (Argmax, Swift): proves billion-scale *streaming* ASR on-device — Whisper Large v3 Turbo on an M3 Max ANE hit **0.46 s streaming latency at 2.2% WER**, matching/beating Deepgram nova-3 and gpt-4o-transcribe in their (vendor-authored, open-methodology) ICML workshop paper. Streaming is likely unnecessary for hold-to-talk given 0.2 s chunked Parakeet, but it's the upgrade path for live-preview text. *(9-0)*
- **whisper.cpp**: the mature fallback — dependency-free C/C++, Apple-Silicon-first (NEON/Accelerate/Metal/CoreML), CoreML encoder can be >3x vs CPU (hedged; Metal is now default and the CoreML edge is smaller). Memory: tiny ~273 MB → large ~3.9 GB RAM. v1.9.1, ~51k stars, powers VoiceInk and MacWhisper. *(8-1)*

**Caveats:** the M4 benchmark measures **speed only, not WER head-to-head** — validate Parakeet vs Whisper large-v3-turbo accuracy on your own voice/jargon before committing (open question #1). VAD: FluidAudio bundles VAD; Silero VAD is the common standalone choice.

---

## 4. Local LLM cleanup via Ollama / LM Studio *(medium confidence, 6-0)*

- **Model class:** ~4B instruction models are sufficient for constrained transcript cleanup. local-whisper defaults to **`gemma3:4b`** ("small, fast, good at text cleanup"). Wispr's own choice of fine-tuned open-weight Llama for this exact step validates the approach. Medium confidence because no verified local latency/quality benchmark for the cleanup step surfaced — **benchmark on your machine** (open question #2).
- **You already have:** `qwen3:latest` (5.2 GB) and `llama3.1` — both usable today. For lowest latency, `ollama pull gemma3:4b` (or `qwen3:4b`).
- **API:** Ollama `localhost:11434` or LM Studio's OpenAI-compatible endpoint — the formatting layer is engine-agnostic.
- **Prompt pattern (source-verified from local-whisper):** narrow system instruction with explicit constraints so the model cleans the dictation instead of *answering* it:

  > "You are a text cleanup tool. Fix punctuation and capitalization. Remove ONLY filler words like um, uh, you know, I mean. Do not add, answer, or rephrase content. Return only the cleaned text."

  Extend with: cleanup-intensity level (None/Light/Medium/High variants), personal-dictionary terms, active-app identity, and near-cursor context.
- **Latency lever:** keep the model loaded (Ollama `keep_alive`), stream tokens, and consider `num_predict` caps. Qwen3 note: use `/no_think` or a non-thinking variant — reasoning tokens would blow the latency budget.

---

## 5. Open-source prior art (repos + licenses verified, 15-0)

| Project | License | Stack | What to take |
|---|---|---|---|
| **Parakey** (rcourtman/parakey) | MIT | Native Swift menu-bar, FluidAudio + Parakeet v3 on ANE, macOS 14+ | The whole macOS shell: hotkey tap, 3-permission model, pasteboard+Cmd+V insertion, ~100 ms release→paste. No LLM layer. Small project (~11 ★, v0.2.20 Jun 2026). |
| **VoiceInk** (beingpax/VoiceInk) | **GPL-3.0** | 99.7% Swift, dual-engine whisper.cpp + FluidAudio, optional opt-in cloud/Ollama | The closest full-featured clone (5,400+ ★, active Jul 2026) — study its dual-engine architecture and Ollama integration. **Copyleft: reuse code only if whisp ships GPL-3.0.** |
| **local-whisper** (luisalima/local-whisper) | MIT | Hammerspoon/Lua | Blueprint of the *complete* pipeline: flagsChanged hold/release → ffmpeg 1 s chunk recording → whisper.cpp → **Ollama gemma3:4b refine** → paste. Self-described "vibe-coded" — a template, not a product. |
| Handy (cjpais/Handy) | MIT | Tauri/Rust, cross-platform | Reference if you ever want Windows/Linux. |
| Whispering (EpicenterHQ) | AGPL-3.0 | Svelte 5 + Tauri (~22 MB) | UI/UX ideas; AGPL caveat. |
| OpenWhispr, VoiceTypr | MIT / — | Electron-ish, Tauri+Rust | More evidence the space is well-trodden; less to reuse. |

No verified clone uses Electron; the quality bar (Parakey, VoiceInk) is native Swift.

---

## 6. Recommended architecture & build plan

**Pipeline:**

```
hold hotkey (flagsChanged CGEvent tap)
  → record mic (AVAudioEngine, 16 kHz mono)
  → on release: STT (FluidAudio + Parakeet TDT v3 CoreML, ANE)     ~0.2 s
  → cleanup (Ollama gemma3:4b, constrained prompt, streaming)      ~0.3–1 s
  → restore-safe pasteboard write + synthetic Cmd+V                 ~instant
```

**Framework:** native **Swift menu-bar app** (SwiftUI + AppKit `NSStatusItem`) — the pattern of every quality reference. Prototype first in script form to de-risk.

### Phase 0 — Pipeline prototype (a day)
Validate the whole loop before writing Swift. Options: adapt **local-whisper** (MIT, Hammerspoon — you have ffmpeg already; `brew install hammerspoon whisper-cpp`) or a ~100-line Python script (sounddevice + mlx-whisper/pywhispercpp + requests→Ollama + pynput/AppleScript paste). **Measure on your M4 Pro:** STT time, Ollama time-to-last-token for gemma3:4b vs qwen3:4b vs llama3.1:8b on 10/30/60-word utterances. This answers open questions #1–2 empirically.

### Phase 1 — Swift MVP: dictation without cleanup (a weekend)
Prereq: `xcode-select --install` (CLT missing on this machine) or full Xcode.
Menu-bar app with: hold-hotkey tap, AVAudioEngine capture, FluidAudio/Parakeet STT, pasteboard+Cmd+V insertion, the 3 permission flows, recording indicator. Copy structure freely from Parakey (MIT). Target: **≤300 ms release→text**.

### Phase 2 — LLM cleanup layer
Ollama/LM Studio client (OpenAI-compatible, engine-agnostic), 4 intensity levels as system prompts, `keep_alive` to hold the model warm, streaming, timeout fallback: **if the LLM call fails or exceeds ~2 s, paste the raw transcript** (never lose the user's words). Target: **≤1.5 s end-to-end** with cleanup.

### Phase 3 — The "Wispr feel"
Personal dictionary (persist terms → inject into STT prompt + LLM prompt; auto-learn from corrections later), context awareness (AX API: focused element's text near cursor + frontmost app bundle ID → prompt; skip secure fields), per-app tone presets, history window, Whisper-engine slot as alternative (VoiceInk's dual-engine pattern), optional WhisperKit streaming for live preview.

**License note:** copy freely from Parakey and local-whisper (MIT); study VoiceInk but don't lift code unless whisp is GPL-3.0.

---

## Open questions to settle empirically (Phase 0)

> **Phase 0 update (2026-07-03):** questions 1–2 are answered empirically — see [BENCHMARKS.md](BENCHMARKS.md). Parakeet chosen as default STT (2.5–3x faster than Whisper, WER comparable on real words, proper nouns misspell on both → dictionary in Phase 3); gemma3:4b with the "v2" constrained prompt chosen for cleanup (TTFT 0.27 s, total 0.4–1.3 s; warm end-to-end **1.27 s** for a 13 s utterance in [prototype/whisp.py](prototype/whisp.py)). Caveat: TTS test audio — validate on real voice.

1. ~~**Parakeet vs Whisper accuracy on *your* voice**~~ — answered on TTS audio; re-validate on real speech.
2. ~~**Local cleanup latency**~~ — answered: comfortably in budget.
3. **Dictionary/context mechanism** — STT prompt injection vs LLM prompt injection vs both; AX API reliability for near-cursor text varies by app.
4. **Command mode / tone adaptation** — Wispr's implementation wasn't resolved; likely app-identity-in-prompt plus an intent-classification step. Defer past MVP.

## Source-quality caveats

Wispr architecture/latency figures come primarily from the Baseten customer case study (vendor marketing, but first-party via Wispr's CTO and corroborated by Wispr's engineering blog and docs). The WhisperKit paper is vendor-authored (M3 Max hardware; workshop paper). The M4 STT benchmark is one machine, speed-only. VoiceInk is local-by-*default*, not local-only (opt-in cloud providers exist). Parakey and local-whisper are small hobby projects — blueprints, not hardened products. Wispr Flow iterates weekly; model versions and numbers are moving targets.

## Key sources

- https://www.baseten.co/resources/customers/wispr-flow/ — Wispr architecture, Llama cleanup, 700 ms p99
- https://wisprflow.ai/post/technical-challenges — latency budget breakdown
- https://wisprflow.ai/ · https://wisprflow.ai/whats-new · https://docs.wisprflow.ai/ — features, cleanup levels, dictionary, context awareness
- https://github.com/anvanvan/mac-whisper-speedtest — 9-engine M4 benchmark
- https://github.com/FluidInference/FluidAudio · https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml — Parakeet-on-ANE stack
- https://arxiv.org/html/2507.10860v1 — WhisperKit streaming ASR paper
- https://github.com/ggml-org/whisper.cpp — fallback engine
- https://github.com/rcourtman/parakey · https://github.com/beingpax/VoiceInk · https://github.com/luisalima/local-whisper — reference implementations
