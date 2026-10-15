import Foundation
import SwiftUI

/// Lưu API key / base URL / model của từng provider vào UserDefaults.
final class SettingsStore: ObservableObject {
    private static let storageKey = "aihub.settings.v1"

    @Published var apiKeys: [String: String] { didSet { persist() } }
    @Published var baseURLs: [String: String] { didSet { persist() } }
    @Published var models: [String: String] { didSet { persist() } }
    @Published var systemPrompt: String { didSet { persist() } }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Persisted.self, from: data) {
            apiKeys = saved.apiKeys
            baseURLs = saved.baseURLs
            models = saved.models
            systemPrompt = saved.systemPrompt
        } else {
            apiKeys = [:]
            baseURLs = [:]
            models = [:]
            systemPrompt = ""
        }
    }

    private struct Persisted: Codable {
        var apiKeys: [String: String]
        var baseURLs: [String: String]
        var models: [String: String]
        var systemPrompt: String
    }

    private func persist() {
        let saved = Persisted(
            apiKeys: apiKeys,
            baseURLs: baseURLs,
            models: models,
            systemPrompt: systemPrompt
        )
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: Helpers

    private static let whitespace = CharacterSet.whitespacesAndNewlines

    func apiKey(for provider: AIProvider) -> String {
        (apiKeys[provider.id] ?? "").trimmingCharacters(in: Self.whitespace)
    }

    func baseURL(for provider: AIProvider) -> String {
        let value = (baseURLs[provider.id] ?? "").trimmingCharacters(in: Self.whitespace)
        return value.isEmpty ? provider.defaultBaseURL : value
    }

    func model(for provider: AIProvider) -> String {
        let value = (models[provider.id] ?? "").trimmingCharacters(in: Self.whitespace)
        return value.isEmpty ? provider.defaultModel : value
    }

    func isConfigured(for provider: AIProvider) -> Bool {
        if !provider.needsAPIKey { return !baseURL(for: provider).isEmpty }
        return !apiKey(for: provider).isEmpty
    }
}
