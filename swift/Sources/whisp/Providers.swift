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
