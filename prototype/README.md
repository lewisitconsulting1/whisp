# whisp prototype

Hold-to-talk local dictation: **hold RIGHT OPTION → speak → release → cleaned text pastes into the focused app.** Fully local: Parakeet TDT 0.6B (MLX) for speech-to-text, gemma3:4b via Ollama for cleanup.

## Run

```bash
cd ~/Documents/Projects/whisp
bench/.venv/bin/python prototype/whisp.py                 # default: gemma3:4b, light cleanup
bench/.venv/bin/python prototype/whisp.py --cleanup off   # raw transcript, fastest
bench/.venv/bin/python prototype/whisp.py --cleanup medium --model llama3.1:latest
bench/.venv/bin/python prototype/whisp.py --hotkey cmd_r  # use right-Command instead
```

Ollama must be running (`ollama serve` or the menu bar app).

## Permissions (one-time)

Grant these to **the terminal app you launch it from** (Terminal/iTerm/etc.) in System Settings → Privacy & Security:

1. **Microphone** — prompted automatically on first recording
2. **Input Monitoring** — needed for the global hotkey listener; macOS prompts, or add the app manually
3. **Accessibility** — needed to post the Cmd+V paste event

After granting Input Monitoring/Accessibility, fully quit and reopen the terminal app.

## What to expect (measured on this M4 Pro, see ../BENCHMARKS.md)

- First launch: ~10 s model load + warmup, plus one-time model downloads
- Release-to-paste: ~0.3–0.5 s without cleanup; ~0.6–1.5 s with light cleanup depending on utterance length
- If Ollama is down or slow (>6 s), the raw transcript is pasted instead — you never lose words
- Latency per stage is printed after every dictation, along with raw vs cleaned text

## Known limitations (prototype scope)

- gemma3:4b occasionally drops a hedge word ("probably") or lightly rewrites casual sentence openers — see the prompt-iteration notes in BENCHMARKS.md
- Proper nouns (PostgreSQL, Wispr, names) misspell without a personal dictionary — that's Phase 3
- Hold-key detection uses pynput; the Swift app (Phase 1) will use a CGEvent tap like Parakey
