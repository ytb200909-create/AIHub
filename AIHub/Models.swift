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
            defaultModel: "gpt-4o-mini",
            commonModels: ["gpt-4o-mini", "gpt-4o", "gpt-4.1", "gpt-4.1-mini", "o3-mini"],
            needsAPIKey: true
        ),
        AIProvider(
            id: "anthropic",
            name: "Anthropic (Claude)",
            symbol: "brain.head.profile",
            apiStyle: .anthropic,
            defaultBaseURL: "https://api.anthropic.com",
            defaultModel: "claude-sonnet-4-0",
            commonModels: ["claude-sonnet-4-0", "claude-opus-4-0", "claude-3-7-sonnet-latest", "claude-3-5-haiku-latest"],
            needsAPIKey: true
        ),
        AIProvider(
            id: "gemini",
            name: "Google Gemini",
            symbol: "wand.and.stars",
            apiStyle: .gemini,
            defaultBaseURL: "https://generativelanguage.googleapis.com",
            defaultModel: "gemini-2.5-flash",
            commonModels: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"],
            needsAPIKey: true
        ),
        AIProvider(
            id: "openrouter",
            name: "OpenRouter (nhiều model)",
            symbol: "globe",
            apiStyle: .openai,
            defaultBaseURL: "https://openrouter.ai/api/v1",
            defaultModel: "openai/gpt-4o-mini",
            commonModels: [
                "openai/gpt-4o-mini",
                "anthropic/claude-3.5-sonnet",
                "google/gemini-2.0-flash-001",
                "meta-llama/llama-3.3-70b-instruct",
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
            defaultModel: "llama-3.3-70b-versatile",
            commonModels: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "qwen-2.5-32b"],
            needsAPIKey: true
        ),
        AIProvider(
            id: "deepseek",
            name: "DeepSeek",
            symbol: "waveform.path",
            apiStyle: .openai,
            defaultBaseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-chat",
            commonModels: ["deepseek-chat", "deepseek-reasoner"],
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
