# Multi-Provider Cleanup Backends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make LewisWhisper's cleanup LLM pluggable — self-hosted servers (remote Ollama / LM Studio) and cloud APIs (OpenAI, Anthropic, OpenRouter, Perplexity, Kimi) — with Local Ollama unchanged as the free default.

**Architecture:** A `CleanupProvider` enum of presets maps onto three request dialects in `CleanupClient` (ollama-native `/api/chat`, OpenAI-compatible `/chat/completions`, Anthropic `/v1/messages`). API keys live in the macOS Keychain via a small `KeychainStore`. `AppSettings` persists provider + per-provider URL/model; the Settings window grows a provider picker, conditional URL/key fields, and a Test button. Spec: `docs/superpowers/specs/2026-07-08-multi-provider-cleanup-design.md`.

**Tech Stack:** Swift 6 (v5 language mode) SPM executable, SwiftUI settings, URLSession, Security.framework (Keychain), new XCTest target for pure logic.

## Global Constraints

- Local Ollama stays the default provider; zero-config behavior must be byte-for-byte today's behavior (`/api/chat`, `keep_alive: "30m"`, `think: false` for qwen3\*, `temperature 0.1`, `num_predict 500`).
- Failure semantics unchanged: any cleanup error/timeout → return the raw transcript. Timeouts: 6 s self-hosted, 10 s cloud.
- `warmUp()` fires only for self-hosted dialects (never spend cloud tokens on warmup).
- API keys: Keychain only (service `com.lewisitconsulting.lewiswhisper`, account `apikey.<provider rawValue>`); never UserDefaults, never printed.
- Cloud dialects omit `temperature` entirely (newer OpenAI/Anthropic models 400 on it); Anthropic model default is `claude-haiku-4-5` (alias exactly as written — no date suffix).
- Cloud privacy caption must state: transcript text goes to the provider; audio never leaves the Mac.
- Build must stay warning-free under `swift build` with only Xcode CLT (no full Xcode assumptions).

---

### Task 1: Test target + CleanupProvider presets

**Files:**
- Modify: `swift/Package.swift`
- Create: `swift/Sources/whisp/Providers.swift`
- Test: `swift/Tests/whispTests/ProvidersTests.swift`

**Interfaces:**
- Consumes: nothing (new leaf module code)
- Produces: `enum APIDialect { case ollama, openai, anthropic }`; `enum CleanupProvider: String, CaseIterable` with cases `localOllama, remoteOllama, lmStudio, openAI, anthropic, openRouter, perplexity, kimi, custom`, and members `displayName: String`, `dialect: APIDialect`, `defaultBaseURL: String`, `urlEditable: Bool`, `needsKey: Bool`, `defaultModel: String`, `isCloud: Bool`. Later tasks rely on these exact names.

- [ ] **Step 1: Add the test target to Package.swift**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "whisp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LewisWhisper", targets: ["whisp"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "whisp",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "whispTests",
            dependencies: ["whisp"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

(Keep any existing `swiftSettings` lines exactly as they are in the current file; only add `products` if missing and the `testTarget`.)

- [ ] **Step 2: Write the failing test**

`swift/Tests/whispTests/ProvidersTests.swift`:

```swift
import XCTest
@testable import whisp

final class ProvidersTests: XCTestCase {
    func testDefaultProviderIsLocalOllamaWithTodaysBehavior() {
        let p = CleanupProvider.localOllama
        XCTAssertEqual(p.dialect, .ollama)
        XCTAssertEqual(p.defaultBaseURL, "http://localhost:11434")
        XCTAssertFalse(p.urlEditable)
        XCTAssertFalse(p.needsKey)
        XCTAssertEqual(p.defaultModel, "gemma3:4b")
        XCTAssertFalse(p.isCloud)
    }

    func testPresetTableMatchesSpec() {
        XCTAssertEqual(CleanupProvider.remoteOllama.dialect, .ollama)
        XCTAssertTrue(CleanupProvider.remoteOllama.urlEditable)
        XCTAssertFalse(CleanupProvider.remoteOllama.needsKey)

        XCTAssertEqual(CleanupProvider.lmStudio.dialect, .openai)
        XCTAssertEqual(CleanupProvider.lmStudio.defaultBaseURL, "http://localhost:1234/v1")
        XCTAssertFalse(CleanupProvider.lmStudio.needsKey)
        XCTAssertFalse(CleanupProvider.lmStudio.isCloud)

        XCTAssertEqual(CleanupProvider.openAI.defaultBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(CleanupProvider.openAI.defaultModel, "gpt-4o-mini")
        XCTAssertTrue(CleanupProvider.openAI.needsKey)
        XCTAssertTrue(CleanupProvider.openAI.isCloud)

        XCTAssertEqual(CleanupProvider.anthropic.dialect, .anthropic)
        XCTAssertEqual(CleanupProvider.anthropic.defaultBaseURL, "https://api.anthropic.com")
        XCTAssertEqual(CleanupProvider.anthropic.defaultModel, "claude-haiku-4-5")

        XCTAssertEqual(CleanupProvider.openRouter.defaultBaseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(CleanupProvider.perplexity.defaultBaseURL, "https://api.perplexity.ai")
        XCTAssertEqual(CleanupProvider.perplexity.defaultModel, "sonar")
        XCTAssertEqual(CleanupProvider.kimi.defaultBaseURL, "https://api.moonshot.ai/v1")

        XCTAssertEqual(CleanupProvider.custom.dialect, .openai)
        XCTAssertTrue(CleanupProvider.custom.urlEditable)
        XCTAssertFalse(CleanupProvider.custom.needsKey)  // key optional
    }

    func testAllCasesHaveNonEmptyDisplayNames() {
        for p in CleanupProvider.allCases {
            XCTAssertFalse(p.displayName.isEmpty, "\(p.rawValue)")
        }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --package-path swift 2>&1 | tail -5`
Expected: FAIL — `cannot find 'CleanupProvider' in scope` (compile error counts as the failing state).

- [ ] **Step 4: Implement Providers.swift**

```swift
import Foundation

enum APIDialect {
    case ollama      // Ollama-native /api/chat (keep_alive, think flags)
    case openai      // OpenAI-compatible /chat/completions
    case anthropic   // Anthropic-native /v1/messages
}

/// Preset table for cleanup backends. Local Ollama is the default — free,
/// private, zero-config. Cloud presets send transcript TEXT to the provider;
/// audio and speech-to-text never leave the Mac.
enum CleanupProvider: String, CaseIterable {
    case localOllama = "local_ollama"
    case remoteOllama = "remote_ollama"
    case lmStudio = "lm_studio"
    case openAI = "openai"
    case anthropic = "anthropic"
    case openRouter = "openrouter"
    case perplexity = "perplexity"
    case kimi = "kimi"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .localOllama: return "Local Ollama (default, free)"
        case .remoteOllama: return "Remote Ollama server"
        case .lmStudio: return "LM Studio server"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .openRouter: return "OpenRouter"
        case .perplexity: return "Perplexity"
        case .kimi: return "Kimi (Moonshot)"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    var dialect: APIDialect {
        switch self {
        case .localOllama, .remoteOllama: return .ollama
        case .anthropic: return .anthropic
        case .lmStudio, .openAI, .openRouter, .perplexity, .kimi, .custom: return .openai
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .localOllama, .remoteOllama: return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .perplexity: return "https://api.perplexity.ai"
        case .kimi: return "https://api.moonshot.ai/v1"
        case .custom: return "http://localhost:8000/v1"
        }
    }

    var urlEditable: Bool {
        switch self {
        case .localOllama, .openAI, .anthropic, .openRouter, .perplexity, .kimi: return false
        case .remoteOllama, .lmStudio, .custom: return true
        }
    }

    var needsKey: Bool {
        switch self {
        case .openAI, .anthropic, .openRouter, .perplexity, .kimi: return true
        case .localOllama, .remoteOllama, .lmStudio, .custom: return false  // custom: optional key still usable
        }
    }

    var defaultModel: String {
        switch self {
        case .localOllama, .remoteOllama: return "gemma3:4b"
        case .lmStudio: return ""  // resolved from /v1/models; empty = server's loaded model
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-haiku-4-5"
        case .openRouter: return "meta-llama/llama-3.3-70b-instruct"
        case .perplexity: return "sonar"
        case .kimi: return "kimi-k2-turbo-preview"
        case .custom: return ""
        }
    }

    /// true when cleanup text leaves this Mac (drives the privacy caption)
    var isCloud: Bool {
        switch self {
        case .localOllama, .lmStudio: return false
        case .remoteOllama: return false  // LAN server — still self-hosted
        case .openAI, .anthropic, .openRouter, .perplexity, .kimi, .custom: return true
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path swift 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed` with 3 tests. (First run compiles FluidAudio for the test bundle — allow a few minutes.)

- [ ] **Step 6: Commit**

```bash
git add swift/Package.swift swift/Sources/whisp/Providers.swift swift/Tests/
git commit -m "Add test target and CleanupProvider preset table"
```

---

### Task 2: KeychainStore

**Files:**
- Create: `swift/Sources/whisp/KeychainStore.swift`
- Test: `swift/Tests/whispTests/KeychainStoreTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `enum KeychainStore` with `static func get(account: String) -> String?`, `static func set(_ value: String, account: String)`, `static func delete(account: String)`. Setting an empty string deletes. Service constant `"com.lewisitconsulting.lewiswhisper"`.

- [ ] **Step 1: Write the failing test**

`swift/Tests/whispTests/KeychainStoreTests.swift`:

```swift
import XCTest
@testable import whisp

final class KeychainStoreTests: XCTestCase {
    let account = "apikey.unittest"

    override func tearDown() {
        KeychainStore.delete(account: account)
        super.tearDown()
    }

    func testRoundTrip() {
        XCTAssertNil(KeychainStore.get(account: account))
        KeychainStore.set("sk-test-123", account: account)
        XCTAssertEqual(KeychainStore.get(account: account), "sk-test-123")
        KeychainStore.set("sk-test-456", account: account)  // update path
        XCTAssertEqual(KeychainStore.get(account: account), "sk-test-456")
        KeychainStore.delete(account: account)
        XCTAssertNil(KeychainStore.get(account: account))
    }

    func testSettingEmptyStringDeletes() {
        KeychainStore.set("sk-test-123", account: account)
        KeychainStore.set("", account: account)
        XCTAssertNil(KeychainStore.get(account: account))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path swift --filter KeychainStoreTests 2>&1 | tail -3`
Expected: FAIL — `cannot find 'KeychainStore' in scope`.

- [ ] **Step 3: Implement KeychainStore.swift**

```swift
import Foundation
import Security

/// Generic-password storage for API keys. Keys never touch UserDefaults.
/// Developer ID signing gives the app a stable identity, so items persist
/// across app updates.
enum KeychainStore {
    static let service = "com.lewisitconsulting.lewiswhisper"

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        guard !value.isEmpty else {
            delete(account: account)
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --package-path swift --filter KeychainStoreTests 2>&1 | tail -3`
Expected: 2 tests pass. (Tests touch the real login keychain under the test runner's identity; the tearDown cleans up.)

- [ ] **Step 5: Commit**

```bash
git add swift/Sources/whisp/KeychainStore.swift swift/Tests/whispTests/KeychainStoreTests.swift
git commit -m "Add KeychainStore for API keys"
```

---

### Task 3: CleanupClient dialects

**Files:**
- Modify: `swift/Sources/whisp/CleanupClient.swift`
- Test: `swift/Tests/whispTests/CleanupClientTests.swift`

**Interfaces:**
- Consumes: `CleanupProvider`, `APIDialect` (Task 1).
- Produces: `CleanupClient.init(provider: CleanupProvider, baseURL: String, model: String, apiKey: String?)` plus a convenience `init(model: String)` that keeps today's local-Ollama behavior for `runSelftest` compatibility. Pure members used by tests and later tasks:
  `func buildRequest(system: String, userText: String) -> URLRequest?`
  `static func parseContent(_ data: Data, dialect: APIDialect) throws -> String`
  `var model: String` (existing), `var provider: CleanupProvider`.
  Async members (signatures unchanged from today): `clean(_:level:dictionary:context:) async -> String`, `warmUp() async`, plus new `test() async -> Result<Double, String>` (latency seconds or error description).

- [ ] **Step 1: Write the failing tests**

`swift/Tests/whispTests/CleanupClientTests.swift`:

```swift
import XCTest
@testable import whisp

final class CleanupClientTests: XCTestCase {
    func body(_ req: URLRequest) -> [String: Any] {
        guard let data = req.httpBody,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    func testOllamaRequestShapeUnchanged() {
        let c = CleanupClient(provider: .localOllama, baseURL: "http://localhost:11434", model: "gemma3:4b", apiKey: nil)
        let req = c.buildRequest(system: "SYS", userText: "hello")!
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertEqual(req.timeoutInterval, 6.0, accuracy: 0.01)
        let b = body(req)
        XCTAssertEqual(b["keep_alive"] as? String, "30m")
        XCTAssertEqual(b["stream"] as? Bool, false)
        let opts = b["options"] as? [String: Any]
        XCTAssertEqual(opts?["num_predict"] as? Int, 500)
        let msgs = b["messages"] as? [[String: String]]
        XCTAssertEqual(msgs?.first?["role"], "system")
        XCTAssertEqual(msgs?.last?["content"], "hello")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testQwenThinkFlagOnlyOnOllamaDialect() {
        let q = CleanupClient(provider: .localOllama, baseURL: "http://localhost:11434", model: "qwen3:8b", apiKey: nil)
        XCTAssertEqual(body(q.buildRequest(system: "s", userText: "u")!)["think"] as? Bool, false)
        let g = CleanupClient(provider: .localOllama, baseURL: "http://localhost:11434", model: "gemma3:4b", apiKey: nil)
        XCTAssertNil(body(g.buildRequest(system: "s", userText: "u")!)["think"])
    }

    func testOpenAIRequestShape() {
        let c = CleanupClient(provider: .openAI, baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", apiKey: "sk-abc")
        let req = c.buildRequest(system: "SYS", userText: "hello")!
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-abc")
        XCTAssertEqual(req.timeoutInterval, 10.0, accuracy: 0.01)
        let b = body(req)
        XCTAssertEqual(b["max_tokens"] as? Int, 500)
        XCTAssertNil(b["temperature"], "cloud dialects omit temperature — newer models 400 on it")
        XCTAssertNil(b["keep_alive"])
    }

    func testLMStudioKeylessOmitsAuthorization() {
        let c = CleanupClient(provider: .lmStudio, baseURL: "http://localhost:1234/v1", model: "", apiKey: nil)
        let req = c.buildRequest(system: "SYS", userText: "hello")!
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(req.timeoutInterval, 6.0, accuracy: 0.01, "self-hosted keeps the short timeout")
    }

    func testAnthropicRequestShape() {
        let c = CleanupClient(provider: .anthropic, baseURL: "https://api.anthropic.com", model: "claude-haiku-4-5", apiKey: "sk-ant-xyz")
        let req = c.buildRequest(system: "SYS", userText: "hello")!
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "sk-ant-xyz")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        let b = body(req)
        XCTAssertEqual(b["system"] as? String, "SYS")
        XCTAssertEqual(b["max_tokens"] as? Int, 500)
        XCTAssertNil(b["temperature"])
        let msgs = b["messages"] as? [[String: String]]
        XCTAssertEqual(msgs?.count, 1)  // system is top-level, not a message
        XCTAssertEqual(msgs?.first?["role"], "user")
    }

    func testParseContentPerDialect() throws {
        let ollama = #"{"message":{"role":"assistant","content":"clean A"}}"#
        XCTAssertEqual(try CleanupClient.parseContent(Data(ollama.utf8), dialect: .ollama), "clean A")
        let openai = #"{"choices":[{"message":{"role":"assistant","content":"clean B"}}]}"#
        XCTAssertEqual(try CleanupClient.parseContent(Data(openai.utf8), dialect: .openai), "clean B")
        let anthropic = #"{"content":[{"type":"text","text":"clean C"}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(try CleanupClient.parseContent(Data(anthropic.utf8), dialect: .anthropic), "clean C")
    }

    func testParseContentThrowsOnErrorPayloads() {
        let apiError = #"{"error":{"message":"invalid api key"}}"#
        XCTAssertThrowsError(try CleanupClient.parseContent(Data(apiError.utf8), dialect: .openai))
        XCTAssertThrowsError(try CleanupClient.parseContent(Data(apiError.utf8), dialect: .anthropic))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --package-path swift --filter CleanupClientTests 2>&1 | tail -3`
Expected: FAIL — no `init(provider:baseURL:model:apiKey:)`, no `buildRequest`.

- [ ] **Step 3: Rewrite CleanupClient.swift**

Keep the existing `Level` enum, all four prompt constants, and `systemPrompt(level:dictionary:context:)` EXACTLY as they are. Replace the struct's stored properties, `ChatResponse`, and the networking half with:

```swift
struct CleanupClient {
    // ... Level enum, prompt constants, systemPrompt(...) unchanged ...

    let provider: CleanupProvider
    let baseURL: String
    let model: String
    let apiKey: String?

    init(provider: CleanupProvider, baseURL: String, model: String, apiKey: String?) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }

    /// Today's zero-config behavior (local Ollama) — used by selftest and as
    /// the fallback when settings are absent.
    init(model: String) {
        self.init(provider: .localOllama, baseURL: CleanupProvider.localOllama.defaultBaseURL, model: model, apiKey: nil)
    }

    var timeout: TimeInterval { provider.isCloud ? 10.0 : 6.0 }

    enum ParseError: Error { case badShape, apiError(String) }

    func buildRequest(system: String, userText: String) -> URLRequest? {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        var payload: [String: Any]
        var urlString: String
        switch provider.dialect {
        case .ollama:
            urlString = base + "/api/chat"
            payload = [
                "model": model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": userText],
                ],
                "stream": false,
                "keep_alive": "30m",
                "options": ["temperature": 0.1, "num_predict": 500],
            ]
            if model.hasPrefix("qwen3") { payload["think"] = false }
        case .openai:
            urlString = base + "/chat/completions"
            payload = [
                "model": model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": userText],
                ],
                "max_tokens": 500,
                "stream": false,
            ]
        case .anthropic:
            urlString = base + "/v1/messages"
            payload = [
                "model": model,
                "max_tokens": 500,
                "system": system,
                "messages": [["role": "user", "content": userText]],
            ]
        }
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch provider.dialect {
        case .openai:
            if let apiKey, !apiKey.isEmpty {
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            req.setValue(apiKey ?? "", forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .ollama:
            break
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return req
    }

    static func parseContent(_ data: Data, dialect: APIDialect) throws -> String {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.badShape
        }
        if let err = obj["error"] {
            let message = ((err as? [String: Any])?["message"] as? String) ?? "\(err)"
            throw ParseError.apiError(message)
        }
        switch dialect {
        case .ollama:
            if let msg = obj["message"] as? [String: Any], let content = msg["content"] as? String {
                return content
            }
        case .openai:
            if let choices = obj["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String {
                return content
            }
        case .anthropic:
            if let blocks = obj["content"] as? [[String: Any]],
               let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String {
                return text
            }
        }
        throw ParseError.badShape
    }

    func warmUp() async {
        guard !provider.isCloud else { return }  // never spend cloud tokens on warmup
        _ = await send(system: Self.systemPrompt(level: .light, dictionary: [], context: nil),
                       userText: "hello", timeoutOverride: 60)
    }

    func clean(_ transcript: String, level: Level, dictionary: [String], context: AppContext?) async -> String {
        guard level != .off else { return transcript }
        let system = Self.systemPrompt(level: level, dictionary: dictionary, context: context)
        if let cleaned = await send(system: system, userText: transcript, timeoutOverride: nil),
           !cleaned.isEmpty {
            return cleaned
        }
        return transcript
    }

    /// Settings "Test" button: round-trip a trivial prompt, return latency or error.
    func test() async -> Result<Double, String> {
        let t0 = Date()
        guard var req = buildRequest(system: "Reply with exactly: OK", userText: "ping") else {
            return .failure("invalid server URL")
        }
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let detail = (try? Self.parseContent(data, dialect: provider.dialect)).map { _ in "" }
                    ?? (String(data: data, encoding: .utf8) ?? "")
                return .failure("HTTP \(http.statusCode): \(detail.prefix(120))")
            }
            _ = try Self.parseContent(data, dialect: provider.dialect)
            return .success(Date().timeIntervalSince(t0))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func send(system: String, userText: String, timeoutOverride: TimeInterval?) async -> String? {
        guard var req = buildRequest(system: system, userText: userText) else { return nil }
        if let timeoutOverride { req.timeoutInterval = timeoutOverride }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let content = try Self.parseContent(data, dialect: provider.dialect)
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            fputs("  cleanup failed (\(error)); inserting raw transcript\n", stderr)
            return nil
        }
    }
}
```

Delete the old `endpoint`/`timeout` stored properties, `ChatResponse` struct, and the two old `clean` overloads — `send` replaces them. The old `clean(_:level:dictionary:context:)` public signature is preserved.

- [ ] **Step 4: Run all tests + build**

Run: `swift test --package-path swift 2>&1 | tail -3 && swift build --package-path swift 2>&1 | tail -1`
Expected: all tests pass; `Build complete!` (main.swift still compiles because `CleanupClient(model:)` convenience init is kept).

- [ ] **Step 5: Live check against local Ollama (behavior unchanged)**

Run: `swift/.build/debug/LewisWhisper --selftest bench/audio/short.wav 2>/dev/null | tail -3`
Expected: `stt … | llm … | total …` under ~2 s with a cleaned transcript — identical behavior to before the refactor.

- [ ] **Step 6: Commit**

```bash
git add swift/Sources/whisp/CleanupClient.swift swift/Tests/whispTests/CleanupClientTests.swift
git commit -m "CleanupClient: three dialects (ollama/openai/anthropic) + Test probe"
```

---

### Task 4: AppSettings provider persistence + key storage

**Files:**
- Modify: `swift/Sources/whisp/Settings.swift` (the `AppSettings` class section)
- Modify: `swift/Sources/whisp/main.swift` (AppController `applySettings()` + `cleaner` construction; selftest provider note)

**Interfaces:**
- Consumes: `CleanupProvider`, `KeychainStore`, `CleanupClient.init(provider:baseURL:model:apiKey:)`.
- Produces on `AppSettings`: `@Published var provider: CleanupProvider`, `@Published var serverURL: String` (per-provider persisted `"serverURL.<raw>"`), `model` becomes per-provider (`"model.<raw>"`), `@Published var apiKey: String` (Keychain-backed mirror, account `"apikey.<raw>"`), and `func makeCleaner() -> CleanupClient`. Migration: legacy `"model"` default seeds `"model.local_ollama"` once.

- [ ] **Step 1: Extend AppSettings**

In `Settings.swift`, replace the `model` property and add provider plumbing:

```swift
    @Published var provider: CleanupProvider {
        didSet {
            persist(provider.rawValue, "cleanupProvider")
            // switching providers swaps in that provider's remembered URL/model/key
            serverURL = UserDefaults.standard.string(forKey: "serverURL.\(provider.rawValue)") ?? provider.defaultBaseURL
            model = UserDefaults.standard.string(forKey: "model.\(provider.rawValue)") ?? provider.defaultModel
            apiKey = KeychainStore.get(account: "apikey.\(provider.rawValue)") ?? ""
        }
    }
    @Published var serverURL: String {
        didSet { persist(serverURL, "serverURL.\(provider.rawValue)") }
    }
    @Published var model: String {
        didSet { persist(model, "model.\(provider.rawValue)") }
    }
    /// Keychain-backed mirror — the string itself is never written to UserDefaults
    @Published var apiKey: String {
        didSet {
            KeychainStore.set(apiKey, account: "apikey.\(provider.rawValue)")
            onChange?()
        }
    }

    func makeCleaner() -> CleanupClient {
        CleanupClient(
            provider: provider,
            baseURL: serverURL.isEmpty ? provider.defaultBaseURL : serverURL,
            model: model.isEmpty ? provider.defaultModel : model,
            apiKey: apiKey.isEmpty ? nil : apiKey
        )
    }
```

And in `init(options:)` replace `self.model = options.model` with:

```swift
        let storedProvider = CleanupProvider(rawValue: d.string(forKey: "cleanupProvider") ?? "") ?? .localOllama
        self.provider = storedProvider
        self.serverURL = d.string(forKey: "serverURL.\(storedProvider.rawValue)") ?? storedProvider.defaultBaseURL
        // migration: pre-provider versions stored a single "model" key
        if d.string(forKey: "model.\(CleanupProvider.localOllama.rawValue)") == nil,
           let legacy = d.string(forKey: "model") {
            d.set(legacy, forKey: "model.\(CleanupProvider.localOllama.rawValue)")
        }
        // CLI --model still wins for this launch when explicitly passed
        self.model = d.string(forKey: "model.\(storedProvider.rawValue)") ?? options.model
        self.apiKey = KeychainStore.get(account: "apikey.\(storedProvider.rawValue)") ?? ""
```

(The `didSet` observers don't fire during init, so this seeds without spuriously persisting — same pattern as the existing fields.)

- [ ] **Step 2: Wire AppController to the provider-aware cleaner**

In `main.swift`:
- In `init(options:)`, replace `self.cleaner = CleanupClient(model: options.model)` with `self.cleaner = CleanupClient(model: options.model)` (unchanged — settings isn't constructed yet), and at the top of `applicationDidFinishLaunching` add `cleaner = settings.makeCleaner()`.
- In `applySettings()`, replace the model-only rebuild:

```swift
        let fresh = settings.makeCleaner()
        if fresh.provider != cleaner.provider || fresh.model != cleaner.model
            || fresh.baseURL != cleaner.baseURL || fresh.apiKey != cleaner.apiKey {
            cleaner = fresh
            print("cleanup → \(fresh.provider.displayName) · \(fresh.model.isEmpty ? "(server default)" : fresh.model)")
            if !fresh.provider.isCloud {
                Task { await self.cleaner.warmUp() }
            }
        }
```

- In `beginStartup()`, change the warm gate from `if self.settings.level != .off` to `if self.settings.level != .off && !self.settings.provider.isCloud`, and print which provider is active.

- [ ] **Step 3: Build + full test suite**

Run: `swift build --package-path swift 2>&1 | tail -1 && swift test --package-path swift 2>&1 | tail -3`
Expected: `Build complete!`; all tests pass.

- [ ] **Step 4: Live selftest (still default local path)**

Run: `swift/.build/debug/LewisWhisper --selftest bench/audio/short.wav 2>/dev/null | tail -3`
Expected: unchanged cleaned output — proves migration + default path intact.

- [ ] **Step 5: Commit**

```bash
git add swift/Sources/whisp/Settings.swift swift/Sources/whisp/main.swift
git commit -m "AppSettings: provider selection, per-provider URL/model, Keychain-backed key"
```

---

### Task 5: Settings UI — provider picker, conditional fields, Test button, privacy caption

**Files:**
- Modify: `swift/Sources/whisp/Settings.swift` (the `SettingsView` Cleanup section + `loadModels`)

**Interfaces:**
- Consumes: everything above. No new public API produced.

- [ ] **Step 1: Replace the Cleanup section of SettingsView**

Replace the current model picker block inside `Section("Cleanup")` with:

```swift
            Section("Cleanup AI") {
                Picker("Provider", selection: $settings.provider) {
                    ForEach(CleanupProvider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }

                if settings.provider.urlEditable {
                    TextField("Server URL", text: $settings.serverURL)
                        .autocorrectionDisabled()
                }

                if settings.provider.needsKey || settings.provider == .custom {
                    SecureField("API key", text: $settings.apiKey)
                }

                Picker("Level", selection: $settings.level) {
                    ForEach(CleanupClient.Level.allCases, id: \.self) { lvl in
                        Text(lvl.menuTitle).tag(lvl)
                    }
                }

                if !installedModels.isEmpty {
                    Picker("Model", selection: $settings.model) {
                        ForEach(installedModels, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    TextField("Model", text: $settings.model,
                              prompt: Text(settings.provider.defaultModel.isEmpty
                                           ? "server's loaded model" : settings.provider.defaultModel))
                }

                HStack {
                    Button("Test") { runTest() }
                        .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    if let result = testResult {
                        Text(result.text)
                            .font(.caption)
                            .foregroundStyle(result.ok ? Color.green : Color.red)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                if settings.provider.isCloud {
                    Text("Transcript text is sent to \(shortName) for cleanup. Audio never leaves this Mac — speech-to-text is always local.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Context awareness", isOn: $settings.contextAware)
                Toggle("Learn new words automatically", isOn: $settings.learnWords)
            }
```

Add state + helpers to `SettingsView`:

```swift
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    private var shortName: String {
        settings.provider.displayName.components(separatedBy: " (").first ?? settings.provider.displayName
    }

    private func runTest() {
        testing = true
        testResult = nil
        let client = settings.makeCleaner()
        Task {
            let result = await client.test()
            await MainActor.run {
                testing = false
                switch result {
                case .success(let seconds):
                    testResult = (true, String(format: "✓ %@ responded in %.1f s", shortName, seconds))
                case .failure(let message):
                    testResult = (false, "✗ \(message)")
                }
            }
        }
    }
```

- [ ] **Step 2: Make `loadModels` provider-aware**

Replace `loadModels()` so the live picker works for Ollama variants (`/api/tags`) and LM Studio (`/v1/models`), and is skipped for cloud:

```swift
    private func loadModels() async {
        installedModels = []
        let base = settings.serverURL.isEmpty ? settings.provider.defaultBaseURL : settings.serverURL
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        var names: [String] = []
        do {
            switch settings.provider {
            case .localOllama, .remoteOllama:
                struct Tags: Decodable { struct M: Decodable { let name: String }; let models: [M] }
                let (data, _) = try await URLSession.shared.data(
                    for: URLRequest(url: URL(string: trimmed + "/api/tags")!, timeoutInterval: 2))
                names = try JSONDecoder().decode(Tags.self, from: data).models.map(\.name).sorted()
            case .lmStudio, .custom:
                struct Models: Decodable { struct M: Decodable { let id: String }; let data: [M] }
                let (data, _) = try await URLSession.shared.data(
                    for: URLRequest(url: URL(string: trimmed + "/models")!, timeoutInterval: 2))
                names = try JSONDecoder().decode(Models.self, from: data).data.map(\.id).sorted()
            default:
                return  // cloud providers: free-text model field with preset default
            }
        } catch {
            return  // unreachable server: leave the free-text field
        }
        if !names.isEmpty {
            if !settings.model.isEmpty, !names.contains(settings.model) {
                names.insert(settings.model, at: 0)
            }
            if settings.model.isEmpty, let first = names.first, settings.provider == .lmStudio {
                settings.model = first
            }
            installedModels = names
        }
    }
```

Also add `.onChange(of: settings.provider) { Task { await loadModels() } }` and `.onChange(of: settings.serverURL) { Task { await loadModels() } }` on the `Form`, and remove the now-dead `ollamaReachable` state + its caption.

- [ ] **Step 3: Build + tests + manual smoke**

Run: `swift build --package-path swift 2>&1 | tail -1 && swift test --package-path swift 2>&1 | tail -3`
Expected: clean build, tests pass.

Manual (requires the human at the keyboard, but the pipeline part is scriptable): run `swift/.build/debug/LewisWhisper` from a terminal, open Settings (⌘,), and verify — provider picker present; choosing "Remote Ollama server" shows a URL field pre-filled `http://localhost:11434`; **Test** with local Ollama running shows `✓ … responded in …s`; choosing OpenAI shows a SecureField and the privacy caption; Test with no key shows `✗ HTTP 401 …`.

- [ ] **Step 4: Live openai-dialect verification via LM Studio**

LM Studio is installed on this Mac. If its CLI is present (`~/.lmstudio/bin/lms`), run `lms server start` and load any small model; otherwise ask the user to toggle "Start server" in LM Studio's Developer tab. Then in Settings pick "LM Studio server" → Test.
Expected: `✓ LM Studio server responded in …s` — proves the openai dialect end-to-end without spending cloud money. (If LM Studio can't be started headlessly, note it and rely on the unit-tested request shapes + user's later cloud test.)

- [ ] **Step 5: Commit**

```bash
git add swift/Sources/whisp/Settings.swift
git commit -m "Settings: provider picker, URL/key fields, Test button, privacy caption"
```

---

### Task 6: Docs, version bump, ship 0.7.0

**Files:**
- Modify: `swift/Info.plist` (0.7.0 / build 9)
- Modify: `docs/setup-guide.html` (Settings row + privacy section + footer version)
- Modify: `swift/README.md`, `README.md` (feature section + roadmap)
- Modify: memory file (auto-memory update happens outside the repo)

**Interfaces:** none — documentation and release mechanics.

- [ ] **Step 1: Bump version**

```bash
sed -i '' -e 's|<string>0.6.1</string>|<string>0.7.0</string>|' swift/Info.plist
sed -i '' '/<key>CFBundleVersion<\/key>/{n;s|<string>8</string>|<string>9</string>|;}' swift/Info.plist
sed -i '' 's/LewisWhisper 0.6.1 &middot;/LewisWhisper 0.7.0 \&middot;/' docs/setup-guide.html
```

- [ ] **Step 2: Update docs**

- `docs/setup-guide.html` — in the Settings table row, extend the description with: *"pick your cleanup AI: your own Ollama/LM Studio server (free) or a cloud provider (OpenAI, Anthropic, OpenRouter, Perplexity, Kimi) with your API key"*. In the Privacy section, append: *"If you choose a cloud cleanup provider in Settings, the transcript text (never audio) is sent to that provider. The default — Local Ollama — keeps everything on this Mac."*
- `swift/README.md` — add a "Phase 7 features" section describing the provider table, Keychain storage, Test button, and the client-office pattern (`http://mac-mini.local:11434`).
- `README.md` — roadmap: `- [x] Phase 7 — pluggable cleanup backends (remote Ollama/LM Studio, cloud APIs), Keychain keys`.

- [ ] **Step 3: Full verification**

```bash
swift test --package-path swift 2>&1 | tail -3
swift build -c release --package-path swift 2>&1 | tail -1
swift/.build/release/LewisWhisper --selftest bench/audio/dict_test.wav 2>/dev/null | tail -3
```
Expected: tests pass; release builds; selftest output shows dictionary corrections working (unchanged local default path).

- [ ] **Step 4: Package, notarize, install, release**

```bash
./scripts/package-app.sh   # sandbox disabled, background — notarization takes minutes
# then: pkill LewisWhisper; cp -RX dist/LewisWhisper.app /Applications/; open it
# stage dist/LewisWhisper-0.7.0/{app, setup.command, guide PDF}; ditto zip
# git add -A; commit "Phase 7: pluggable cleanup backends (0.7.0)"; push
# gh release create v0.7.0 dist/LewisWhisper-0.7.0.zip --title "LewisWhisper 0.7.0" --notes "<provider feature notes>"
```
Expected: notarization `Accepted`; permissions survive (same signing identity); release URL prints.

- [ ] **Step 5: Post-ship user validation (needs Chadwick)**

Ask Chadwick to: (a) point Remote Ollama at the office Mac mini when he's on that LAN and hit Test; (b) paste a real cloud API key (any provider) into Settings and hit Test, then dictate once with cloud cleanup to confirm end-to-end.

---

## Self-review notes

- **Spec coverage:** provider table ✓ (Task 1), three dialects + timeouts + warmUp gating ✓ (Task 3), Keychain ✓ (Task 2), per-provider URL/model memory + migration ✓ (Task 4), Settings UI + Test + privacy caption ✓ (Task 5), docs/release ✓ (Task 6). LM Studio empty-model fallback ✓ (Tasks 1/5).
- **Type consistency:** `CleanupProvider` members used in Tasks 3–5 match Task 1's definitions; `CleanupClient` async signatures match existing call sites in `main.swift` (`clean(_:level:dictionary:context:)`, `warmUp()`); `makeCleaner()` produced in Task 4 and consumed in Tasks 4–5.
- **Known judgment calls encoded:** cloud dialects omit `temperature` (model-generation 400 foot-gun); OpenAI default stays `gpt-4o-mini` (accepts `max_tokens`; newer o-series/gpt-5 models may require `max_completion_tokens` — Test button surfaces it, documented as a future tweak); `remoteOllama.isCloud == false` so no privacy caption for LAN servers (traffic stays on the user's network).
