import Foundation

// MARK: - API style

/// Kiểu API mà provider dùng.
/// - openai:    chuẩn OpenAI `/chat/completions` (cũng dùng cho Groq, DeepSeek, OpenRouter, Ollama, custom...)
/// - anthropic: Anthropic Messages API `/v1/messages`
/// - gemini:    Google Gemini `streamGenerateContent`
enum APIStyle: String, Codable {
    case openai
    case anthropic
    case gemini
}

// MARK: - Provider

struct AIProvider: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let symbol: String
    let apiStyle: APIStyle
    let defaultBaseURL: String
    let defaultModel: String
    let commonModels: [String]
    let needsAPIKey: Bool
}

enum Providers {
    static let all: [AIProvider] = [
        AIProvider(
            id: "openai",
            name: "OpenAI (ChatGPT)",
            symbol: "sparkles",
            apiStyle: .openai,
            defaultBaseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-6.1-sol",
            commonModels: ["gpt-6.1-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.4-mini"],
            needsAPIKey: true
        ),
        AIProvider(
            id: "anthropic",
            name: "Anthropic (Claude)",
            symbol: "brain.head.profile",
            apiStyle: .anthropic,
            defaultBaseURL: "https://api.anthropic.com",
            defaultModel: "claude-sonnet-5-5",
            commonModels: ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5", "claude-fable-5-1"],
            needsAPIKey: true
        ),
        AIProvider(
            id: "gemini",
            name: "Google Gemini",
            symbol: "wand.and.stars",
            apiStyle: .gemini,
            defaultBaseURL: "https://generativelanguage.googleapis.com",
            defaultModel: "gemini-flash-latest",
            commonModels: ["gemini-flash-latest", "gemini-3.8-flash", "gemini-3.5-flash", "gemini-pro-latest", "gemini-flash-lite-latest"],
            needsAPIKey: true
        ),
        AIProvider(
            id: "openrouter",
            name: "OpenRouter (nhiều model)",
            symbol: "globe",
            apiStyle: .openai,
            defaultBaseURL: "https://openrouter.ai/api/v1",
            defaultModel: "google/gemma-4-31b-it:free",
            commonModels: [
                "google/gemma-4-31b-it:free",
                "nvidia/nemotron-3.5-super-vl:free",
                "thinkingmachines/inkling:free",
                "openai/gpt-4o-mini",
                "deepseek/deepseek-chat"
            ],
            needsAPIKey: true
        ),
        AIProvider(
            id: "groq",
            name: "Groq (rất nhanh)",
            symbol: "bolt.fill",
            apiStyle: .openai,
            defaultBaseURL: "https://api.groq.com/openai/v1",
            defaultModel: "openai/gpt-oss-120b",
            commonModels: ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b", "allam-2-7b"],
            needsAPIKey: true
        ),
        AIProvider(
            id: "deepseek",
            name: "DeepSeek",
            symbol: "waveform.path",
            apiStyle: .openai,
            defaultBaseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-chat",
            commonModels: ["deepseek-chat", "deepseek-reasoner", "deepseek-v4.1-flash", "deepseek-v4-pro"],
            needsAPIKey: true
        ),
        AIProvider(
            id: "ollama",
            name: "Ollama (chạy local)",
            symbol: "desktopcomputer",
            apiStyle: .openai,
            defaultBaseURL: "http://localhost:11434/v1",
            defaultModel: "llama3.1:8b",
            commonModels: ["llama3.1:8b", "llama3.2", "qwen2.5", "mistral"],
            needsAPIKey: false
        ),
        AIProvider(
            id: "custom",
            name: "Tùy chỉnh (OpenAI-compatible)",
            symbol: "slider.horizontal.3",
            apiStyle: .openai,
            defaultBaseURL: "",
            defaultModel: "",
            commonModels: [],
            needsAPIKey: false
        ),
    ]

    static func byID(_ id: String) -> AIProvider {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Chat models

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

struct ImageAttachment: Codable, Equatable {
    var base64: String
    var mimeType: String
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var role: MessageRole
    var text: String
    var images: [ImageAttachment]? = nil
}

struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String = "Chat mới"
    var providerID: String = Providers.all[0].id
    var createdAt: Date = Date()
    var messages: [ChatMessage] = []
}
