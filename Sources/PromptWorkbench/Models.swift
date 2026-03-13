import AppKit

// MARK: - Providers

enum LLMProvider: String, CaseIterable, Codable {
    case anthropic = "Anthropic"
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-6"
        case .openAI: return "gpt-5.4"
        case .openRouter: return "google/gemini-3-flash-preview"
        }
    }

    var models: [String] {
        switch self {
        case .anthropic: return [
            "claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5-20251001",
        ]
        case .openAI: return [
            "gpt-5.4", "gpt-5.4-pro", "gpt-5.2-pro", "o3-pro", "o3", "o4-mini", "gpt-4.1", "gpt-4.1-mini",
        ]
        case .openRouter: return [
            "google/gemini-3-flash-preview", "google/gemini-3.1-pro-preview", "deepseek/deepseek-v3.2",
            "anthropic/claude-sonnet-4-6", "openai/gpt-5.4", "qwen/qwen3.5-plus-02-15",
            "mistralai/mistral-large-2512", "meta-llama/llama-3.3-70b-instruct", "inception/mercury-2",
        ]
        }
    }

    var accentColor: NSColor {
        switch self {
        case .anthropic: return NSColor(red: 0.90, green: 0.52, blue: 0.20, alpha: 1.0)
        case .openAI: return NSColor(red: 0.25, green: 0.75, blue: 0.60, alpha: 1.0)
        case .openRouter: return NSColor(red: 0.48, green: 0.45, blue: 0.98, alpha: 1.0)
        }
    }

    var iconSymbol: String {
        switch self {
        case .anthropic: return "brain.head.profile.fill"
        case .openAI: return "sparkles"
        case .openRouter: return "arrow.triangle.branch"
        }
    }

    var apiKeySettingsKey: String { "apiKey_\(rawValue)" }

    var apiKey: String? {
        get { UserDefaults.standard.string(forKey: apiKeySettingsKey) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: apiKeySettingsKey) }
    }
}

// MARK: - Chat & Streaming

struct ChatMessage: Codable {
    let role: String   // "system", "user", "assistant"
    let content: String
    let timestamp: Date

    init(role: String, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

struct StreamToken {
    let text: String
    let inputTokens: Int?
    let outputTokens: Int?
    let done: Bool
}

// MARK: - History

struct ProviderResponse: Codable {
    let provider: String
    let model: String
    let messages: [ChatMessage]
    let inputTokens: Int?
    let outputTokens: Int?
    let durationSeconds: Double?
    let error: String?
}

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let systemPrompt: String?
    let userPrompt: String
    let temperature: Double
    let responses: [ProviderResponse]
}
