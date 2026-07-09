# Multi-provider cleanup backends — design

**Date:** 2026-07-08 · **Status:** approved (Chadwick, in-chat)
**Goal:** the cleanup LLM becomes pluggable — self-hosted servers (a client-office Mac mini running Ollama or LM Studio) and cloud APIs (OpenAI, Anthropic, OpenRouter, Perplexity, Kimi) — while **Local Ollama stays the default: free, private, zero-config**. Speech-to-text is local always and is out of scope here.

## Non-goals

- No fleet/preconfigured deployment (client installs are configured by hand in Settings — one URL).
- No VPN/remote-access tooling; self-hosted servers are assumed reachable on the LAN.
- No streaming, retries, or per-provider model catalogs for cloud providers.
- No change to STT, hotkeys, dictionary, tones, or failure philosophy.

## Provider model

New `CleanupProvider` enum (raw string, persisted). Each case is a preset:

| Provider | Dialect | Base URL (editable where noted) | API key | Default model |
|---|---|---|---|---|
| `localOllama` (default) | ollama | `http://localhost:11434` (fixed) | — | `gemma3:4b` |
| `remoteOllama` | ollama | user-entered, e.g. `http://mac-mini.local:11434` | — | `gemma3:4b` |
| `lmStudio` | openai | user-entered, default `http://localhost:1234/v1` | — | server's loaded model |
| `openAI` | openai | `https://api.openai.com/v1` | required | `gpt-4o-mini` * |
| `anthropic` | anthropic | `https://api.anthropic.com` | required | `claude-haiku-4-5` * |
| `openRouter` | openai | `https://openrouter.ai/api/v1` | required | `meta-llama/llama-3.3-70b-instruct` * |
| `perplexity` | openai | `https://api.perplexity.ai` | required | `sonar` * |
| `kimi` | openai | `https://api.moonshot.ai/v1` | required | `kimi-k2-turbo-preview` * |
| `custom` | openai | user-entered | optional | user-entered |

\* Cloud default-model IDs are **verified against provider docs at implementation time** (they drift); all are editable text.

Presets carry: display name, dialect, base URL (+ whether editable), needs-key flag, default model, and a short privacy caption.

## Dialects (3 request shapes in CleanupClient)

1. **ollama** — existing `/api/chat` payload, unchanged: `stream:false`, `keep_alive:"30m"`, `options{temperature:0.1, num_predict:500}`, `think:false` for qwen3\*. Used by localOllama + remoteOllama.
2. **openai** — `POST {base}/chat/completions`, `Authorization: Bearer <key>` (omitted when keyless, e.g. LM Studio), body `{model, messages:[system,user], temperature:0.1, max_tokens:500, stream:false}`; response `choices[0].message.content`. Used by lmStudio, openAI, openRouter, perplexity, kimi, custom. LM Studio's model field defaults to the first entry returned by `/v1/models`; if the list can't be fetched an empty model string is sent, which LM Studio resolves to its currently-loaded model.
3. **anthropic** — `POST {base}/v1/messages`, headers `x-api-key`, `anthropic-version: 2023-06-01`, body `{model, max_tokens:500, temperature:0.1, system, messages:[user]}`; response `content[0].text`. (Exact header/shape re-checked against the claude-api reference during implementation.)

System prompt assembly (levels, dictionary, context/tones) is dialect-independent and unchanged.

**Timeouts:** 6 s self-hosted (unchanged), 10 s cloud. **warmUp:** self-hosted dialect only (free); never for cloud (costs money).

## Settings & persistence

`AppSettings` additions (same UserDefaults-backed pattern):

- `provider: CleanupProvider` — default `.localOllama`. Key `"cleanupProvider"`.
- `serverURL: String` — persisted **per provider** (`"serverURL.<id>"`) so switching presets round-trips.
- `model: String` — now persisted **per provider** (`"model.<id>"`); switching providers restores that provider's last model or its preset default. Migration: existing `"model"` value seeds `"model.localOllama"`.
- **API keys in the macOS Keychain** — generic password, service `com.lewisitconsulting.lewiswhisper`, account `apikey.<provider>`. Never UserDefaults, never logged. (Developer ID signing gives the app a stable identity, so items persist across updates.) A small `KeychainStore` helper wraps SecItem calls.

`CleanupClient` is rebuilt from settings whenever provider/model/URL/key changes (existing `applySettings()` path).

## Settings UI (Cleanup section)

- **Provider** picker listing the presets with plain-language labels ("Local Ollama — free, default", "Remote Ollama server (e.g. office Mac mini)", …).
- Contextual fields: **Server URL** (self-hosted/custom), **API key** (SecureField, cloud/custom), **Model** (live picker via `/api/tags` for Ollama variants and `/v1/models` for LM Studio; text field with preset default for cloud).
- **Test** button: sends "Reply with OK" through the configured provider; shows ✓ latency or the error inline. Catches bad keys/URLs in Settings instead of as silent raw-paste later.
- Privacy caption when a cloud provider is selected: *"Transcript text is sent to {provider} for cleanup. Audio never leaves this Mac — speech-to-text is always local."* Same nuance added to the setup guide + README privacy sections.

## Failure behavior

Unchanged: any error/timeout → paste the raw transcript (never lose words), diagnostic to stderr. The Test button exists so misconfiguration is discoverable.

## Testing

- Build + `--selftest` (reads persisted provider settings) against: local Ollama (default path), LM Studio on this Mac (openai dialect, keyless), remote-URL round-trip (localhost pointed at itself as "remote").
- Cloud dialects: request-shape verified against provider docs; live test after Chadwick pastes a real key into Settings (Test button).
- Keychain: store/read/delete round-trip via the Test flow.

## Docs

setup-guide.html (Settings table + privacy), swift/README (Phase 7 section), root README (privacy line + roadmap), release notes.
