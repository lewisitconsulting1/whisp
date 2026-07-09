import Testing
import Foundation
@testable import whisp

struct CleanupClientTests {
    private func body(_ req: URLRequest) -> [String: Any] {
        guard let data = req.httpBody,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    @Test func ollamaRequestShapeUnchanged() {
        let c = CleanupClient(provider: .localOllama, baseURL: "http://localhost:11434", model: "gemma3:4b", apiKey: nil)
        let req = c.buildRequest(system: "SYS", userText: "hello")!
        #expect(req.url?.absoluteString == "http://localhost:11434/api/chat")
        #expect(abs(req.timeoutInterval - 6.0) < 0.01)
        let b = body(req)
        #expect(b["keep_alive"] as? String == "30m")
        #expect(b["stream"] as? Bool == false)
        let opts = b["options"] as? [String: Any]
        #expect(opts?["num_predict"] as? Int == 500)
        let msgs = b["messages"] as? [[String: String]]
        #expect(msgs?.first?["role"] == "system")
        #expect(msgs?.last?["content"] == "hello")
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func qwenThinkFlagOnlyOnOllamaDialect() {
        let q = CleanupClient(provider: .localOllama, baseURL: "http://localhost:11434", model: "qwen3:8b", apiKey: nil)
        #expect(body(q.buildRequest(system: "s", userText: "u")!)["think"] as? Bool == false)
        let g = CleanupClient(provider: .localOllama, baseURL: "http://localhost:11434", model: "gemma3:4b", apiKey: nil)
        #expect(body(g.buildRequest(system: "s", userText: "u")!)["think"] == nil)
    }

    @Test func openAIRequestShape() {
        let c = CleanupClient(provider: .openAI, baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", apiKey: "sk-abc")
        let req = c.buildRequest(system: "SYS", userText: "hello")!
        #expect(req.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-abc")
        #expect(abs(req.timeoutInterval - 10.0) < 0.01)
        let b = body(req)
        #expect(b["max_tokens"] as? Int == 500)
        #expect(b["temperature"] == nil, "cloud dialects omit temperature — newer models 400 on it")
        #expect(b["keep_alive"] == nil)
    }

    @Test func lmStudioKeylessOmitsAuthorizationAndKeepsShortTimeout() {
        let c = CleanupClient(provider: .lmStudio, baseURL: "http://localhost:1234/v1", model: "", apiKey: nil)
        let req = c.buildRequest(system: "SYS", userText: "hello")!
        #expect(req.url?.absoluteString == "http://localhost:1234/v1/chat/completions")
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(abs(req.timeoutInterval - 6.0) < 0.01)
    }

    @Test func anthropicRequestShape() {
        let c = CleanupClient(provider: .anthropic, baseURL: "https://api.anthropic.com", model: "claude-haiku-4-5", apiKey: "sk-ant-xyz")
        let req = c.buildRequest(system: "SYS", userText: "hello")!
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant-xyz")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        let b = body(req)
        #expect(b["system"] as? String == "SYS")
        #expect(b["max_tokens"] as? Int == 500)
        #expect(b["temperature"] == nil)
        let msgs = b["messages"] as? [[String: String]]
        #expect(msgs?.count == 1)  // system is top-level, not a message
        #expect(msgs?.first?["role"] == "user")
    }

    @Test func trailingSlashInBaseURLIsHandled() {
        let c = CleanupClient(provider: .remoteOllama, baseURL: "http://mac-mini.local:11434/", model: "gemma3:4b", apiKey: nil)
        #expect(c.buildRequest(system: "s", userText: "u")?.url?.absoluteString == "http://mac-mini.local:11434/api/chat")
    }

    @Test func parseContentPerDialect() throws {
        let ollama = #"{"message":{"role":"assistant","content":"clean A"}}"#
        #expect(try CleanupClient.parseContent(Data(ollama.utf8), dialect: .ollama) == "clean A")
        let openai = #"{"choices":[{"message":{"role":"assistant","content":"clean B"}}]}"#
        #expect(try CleanupClient.parseContent(Data(openai.utf8), dialect: .openai) == "clean B")
        let anthropic = #"{"content":[{"type":"text","text":"clean C"}],"stop_reason":"end_turn"}"#
        #expect(try CleanupClient.parseContent(Data(anthropic.utf8), dialect: .anthropic) == "clean C")
    }

    @Test func parseContentThrowsOnErrorPayloads() {
        let apiError = Data(#"{"error":{"message":"invalid api key"}}"#.utf8)
        #expect(throws: (any Error).self) { try CleanupClient.parseContent(apiError, dialect: .openai) }
        #expect(throws: (any Error).self) { try CleanupClient.parseContent(apiError, dialect: .anthropic) }
        #expect(throws: (any Error).self) { try CleanupClient.parseContent(Data("not json".utf8), dialect: .ollama) }
    }
}
