# whisp Phase 0 benchmarks — measured on this machine

**Machine:** Apple M4 Pro, 48 GB RAM, macOS 27.0 · **Date:** 2026-07-03
**Method:** synthesized test utterances (macOS `say`, 16 kHz mono WAV) with known ground-truth text; engines run sequentially with nothing else heavy on the machine; warm times are best-of-3 with the model resident. Scripts: [bench/stt_bench.py](bench/stt_bench.py), [bench/llm_bench.py](bench/llm_bench.py); raw results in [bench/results/](bench/results/).

## Speech-to-text

Warm per-utterance transcription time (audio length in parens) and WER vs ground truth:

| Engine | short (5 s) | medium (14.5 s) | long (26 s) | medium-UK (15 s) | WER m / l / uk |
|---|---|---|---|---|---|
| **parakeet-mlx TDT 0.6B v3** | **0.14 s** | **0.23 s** | **0.37 s** | **0.23 s** | 8.9 / 14.8 / 11.1 % |
| mlx-whisper large-v3-turbo | 0.47 s | 0.57 s | 0.73 s | 0.57 s | 4.4 / 14.8 / 6.7 % |
| whisper.cpp base.en (CLI¹) | 0.24 s | 0.33 s | 0.47 s | 0.32 s | 6.7 / 14.8 / 11.1 % |
| whisper.cpp large-v3-turbo (CLI¹) | 1.02 s | 1.15 s | 1.34 s | 1.17 s | 4.4 / 10.2 / 13.3 % |

¹ CLI times include process spawn + model load per call (the realistic cost of a subprocess integration).

**Reading the WER numbers:** error inspection shows they are dominated by proper-noun spellings (PostgreSQL → "PostGur SQL", Priya Nguyen → "pre-a-win", Ollama → "Alema", Wispr Flow → "Whisperflow") and normalization ("1.5" vs "one and a half", "end-to-end" hyphenation). Real word errors were rare (worst: "fail of a test" for "failover test" on the UK voice). This is precisely the class of error Wispr's personal dictionary + context awareness targets (Phase 3). Whisper large-v3-turbo is a few points better on proper nouns; Parakeet is 2.5–3x faster.

**Decision: Parakeet TDT 0.6B v3 (MLX) as the default engine**, Whisper large-v3-turbo as the accuracy-mode alternative — the same dual-engine pattern VoiceInk ships. First transcription in a fresh process pays ~1.3 s of MLX warmup; the prototype does a dummy transcription at startup to absorb it.

**Caveats:** TTS audio, not a real human voice (validate on your own speech); one machine; four samples; speed-representative but WER indicative only.

## LLM transcript cleanup (Ollama, streaming, warm, best-of-3)

Constrained cleanup prompt; filler-laden inputs of 12 / 35 / 65 words:

| Model | TTFT | short total | medium total | long total | Quality (v1 prompt) |
|---|---|---|---|---|---|
| **gemma3:4b** | 0.27 s | **0.39 s** | **0.60 s** | **1.27 s** | best formatting; dropped a phrase on medium (fixed by v2 prompt) |
| llama3.1:8b | 0.13 s | 0.36 s | 0.82 s | 1.79 s | never loses content; misses some fillers; meta-commentary on long |
| qwen3:8b | 0.11 s | 0.30 s | 0.84 s | 1.73 s | strips punctuation instead of fixing it |
| qwen3:4b | 0.11 s | — | — | — | disqualified: `think:false` not honored, leaks chain-of-thought |

**Prompt iteration (gemma3:4b):**
- **v1** (short instruction): dropped "probably move the standup to" from the medium input — content loss.
- **v2** (numbered rules + "every non-filler word must appear in order" + one-shot example): perfect on short and medium; mild first-sentence rewrite on a casual long opener. **Winner.**
- **v3** (even stronger preservation rules + fragment example): over-corrected — the model started keeping the fillers themselves. Regression.

The preservation-vs-cleanup tradeoff is prompt-sensitive at 4B scale; v2 is the measured sweet spot. Occasional single-word drops ("probably") still occur — the durable fix is Wispr's own approach (a model fine-tuned for cleanup) or an 8B model when quality > latency.

**Decision: gemma3:4b with the v2 prompt** (now the `light` mode in [prototype/whisp.py](prototype/whisp.py)); llama3.1:8b as the conservative fallback.

## End-to-end pipeline (prototype code path)

13.3 s filler-laden utterance (41 words) → Parakeet → gemma3:4b (v2) → cleaned text:

| Path | STT | LLM | Total |
|---|---|---|---|
| Cold (fresh process, no warmup) | 1.50 s | 1.02 s | 2.52 s |
| **Warm (as the prototype runs)** | **0.28 s** | **0.99 s** | **1.27 s** |

Cleanup verified: "So um, I was thinking that we should, uh, probably move the stand-up to, you know, Thursday morning…" → "I was thinking that we should move the stand-up to Thursday morning because half the team is traveling on Wednesday and it just makes more sense that way."

Extrapolating from the component numbers, a typical short dictation (~5 s of speech) lands around **0.5–0.7 s** release-to-paste with cleanup, and **~0.2 s** without — matching Wispr Flow's 700 ms cloud p99, fully offline.

**Phase 1 update (2026-07-07):** the native Swift app (FluidAudio/CoreML on the Neural Engine, `swift/.build/release/whisp --selftest`) runs the same 13.3 s utterance at **stt 0.11 s | llm 1.00 s | total 1.11 s** — the Swift STT path is ~2.5x faster than the Python parakeet-mlx path (0.28 s), with identical transcript and cleanup output. First-ever model download + ANE compile is a one-time ~30 min; cached loads take seconds.

## Open questions from RESEARCH.md — answered

1. **Parakeet vs Whisper accuracy:** comparable on real words; both misspell proper nouns; Parakeet 2.5–3x faster → Parakeet default + dictionary work in Phase 3. (Still validate on real voice.)
2. **Local cleanup latency:** yes, comfortably in budget — gemma3:4b does TTFT 0.27 s, total 0.4–1.3 s for 12–65-word inputs; well under the ~1.5 s end-to-end target.
