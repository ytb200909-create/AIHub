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
    var isFreeTier: Bool = true
    /// true nếu MỌI model của provider đều nhận ảnh (OpenAI/Claude/Gemini).
    var supportsVision: Bool = false
    /// Danh sách model nhận ảnh (khi chỉ một số model hỗ trợ vision).
    var visionModels: [String] = []

    /// Model này có nhận ảnh không?
    func supportsImages(model: String) -> Bool {
        if visionModels.isEmpty { return supportsVision }
        let name = model.lowercased()
        return visionModels.contains { name.contains($0.lowercased()) }
    }
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
            commonModels: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1", "o4-mini"],
            needsAPIKey: true,
            isFreeTier: false,
            supportsVision: true
        ),
        AIProvider(
            id: "anthropic",
            name: "Anthropic (Claude)",
            symbol: "brain.head.profile",
            apiStyle: .anthropic,
            defaultBaseURL: "https://api.anthropic.com",
            defaultModel: "claude-sonnet-4-5",
            commonModels: ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-1", "claude-3-5-haiku-latest"],
            needsAPIKey: true,
            isFreeTier: false,
            supportsVision: true
        ),
        AIProvider(
            id: "gemini",
            name: "Google Gemini",
            symbol: "wand.and.stars",
            apiStyle: .gemini,
            defaultBaseURL: "https://generativelanguage.googleapis.com",
            defaultModel: "gemini-2.5-flash",
            commonModels: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash", "gemini-flash-latest", "gemini-flash-lite-latest"],
            needsAPIKey: true,
            supportsVision: true
        ),
        AIProvider(
            id: "openrouter",
            name: "OpenRouter (nhiều model)",
            symbol: "globe",
            apiStyle: .openai,
            defaultBaseURL: "https://openrouter.ai/api/v1",
            defaultModel: "google/gemma-3-27b-it:free",
            commonModels: [
                "google/gemma-3-27b-it:free",
                "meta-llama/llama-3.3-70b-instruct:free",
                "deepseek/deepseek-chat-v3-0324:free",
                "qwen/qwen3-30b-a3b:free",
                "openai/gpt-4o-mini"
            ],
            needsAPIKey: true,
            visionModels: ["gemma-3", "gemini", "gpt-4o"]
        ),
        AIProvider(
            id: "groq",
            name: "Groq (rất nhanh)",
            symbol: "bolt.fill",
            apiStyle: .openai,
            defaultBaseURL: "https://api.groq.com/openai/v1",
            defaultModel: "llama-3.3-70b-versatile",
            commonModels: [
                "llama-3.3-70b-versatile",
                "meta-llama/llama-4-scout-17b-16e-instruct",
                "meta-llama/llama-4-maverick-17b-128e-instruct",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b"
            ],
            needsAPIKey: true,
            visionModels: ["llama-4-scout", "llama-4-maverick"]
        ),
        AIProvider(
            id: "deepseek",
            name: "DeepSeek",
            symbol: "waveform.path",
            apiStyle: .openai,
            defaultBaseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-chat",
            commonModels: ["deepseek-chat", "deepseek-reasoner", "deepseek-v4.1-flash", "deepseek-v4-pro"],
            needsAPIKey: true,
            isFreeTier: false
        ),
        AIProvider(
            id: "ollama",
            name: "Ollama (chạy local)",
            symbol: "desktopcomputer",
            apiStyle: .openai,
            defaultBaseURL: "http://localhost:11434/v1",
            defaultModel: "llama3.1:8b",
            commonModels: ["llama3.1:8b", "llama3.2", "llama3.2-vision", "qwen2.5", "mistral"],
            needsAPIKey: false,
            visionModels: ["llama3.2-vision", "llava", "gemma3", "minicpm-v", "moondream"]
        ),
        AIProvider(
            id: "custom",
            name: "Tùy chỉnh (OpenAI-compatible)",
            symbol: "slider.horizontal.3",
            apiStyle: .openai,
            defaultBaseURL: "",
            defaultModel: "",
            commonModels: [],
            needsAPIKey: false,
            supportsVision: true
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
