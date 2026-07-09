import Testing
@testable import whisp

struct ProvidersTests {
    @Test func defaultProviderIsLocalOllamaWithTodaysBehavior() {
        let p = CleanupProvider.localOllama
        #expect(p.dialect == .ollama)
        #expect(p.defaultBaseURL == "http://localhost:11434")
        #expect(!p.urlEditable)
        #expect(!p.needsKey)
        #expect(p.defaultModel == "gemma3:4b")
        #expect(!p.isCloud)
    }

    @Test func presetTableMatchesSpec() {
        #expect(CleanupProvider.remoteOllama.dialect == .ollama)
        #expect(CleanupProvider.remoteOllama.urlEditable)
        #expect(!CleanupProvider.remoteOllama.needsKey)

        #expect(CleanupProvider.lmStudio.dialect == .openai)
        #expect(CleanupProvider.lmStudio.defaultBaseURL == "http://localhost:1234/v1")
        #expect(!CleanupProvider.lmStudio.needsKey)
        #expect(!CleanupProvider.lmStudio.isCloud)

        #expect(CleanupProvider.openAI.defaultBaseURL == "https://api.openai.com/v1")
        #expect(CleanupProvider.openAI.defaultModel == "gpt-4o-mini")
        #expect(CleanupProvider.openAI.needsKey)
        #expect(CleanupProvider.openAI.isCloud)

        #expect(CleanupProvider.anthropic.dialect == .anthropic)
        #expect(CleanupProvider.anthropic.defaultBaseURL == "https://api.anthropic.com")
        #expect(CleanupProvider.anthropic.defaultModel == "claude-haiku-4-5")

        #expect(CleanupProvider.openRouter.defaultBaseURL == "https://openrouter.ai/api/v1")
        #expect(CleanupProvider.perplexity.defaultBaseURL == "https://api.perplexity.ai")
        #expect(CleanupProvider.perplexity.defaultModel == "sonar")
        #expect(CleanupProvider.kimi.defaultBaseURL == "https://api.moonshot.ai/v1")

        #expect(CleanupProvider.custom.dialect == .openai)
        #expect(CleanupProvider.custom.urlEditable)
        #expect(!CleanupProvider.custom.needsKey)  // key optional
    }

    @Test func allCasesHaveNonEmptyDisplayNames() {
        for p in CleanupProvider.allCases {
            #expect(!p.displayName.isEmpty, "\(p.rawValue)")
        }
    }
}
