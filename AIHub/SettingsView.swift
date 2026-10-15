import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $settings.systemPrompt)
                        .frame(minHeight: 90)
                } header: {
                    Text("System Prompt")
                } footer: {
                    Text("Chỉ dẫn hệ thống áp dụng cho tất cả các AI. Ví dụ: \"Trả lời ngắn gọn bằng tiếng Việt.\"")
                }

                ForEach(Providers.all) { provider in
                    Section {
                        if provider.needsAPIKey {
                            HStack {
                                SecureField("API Key", text: dictBinding(\.apiKeys, provider.id))
                                statusDot(provider)
                            }
                        }
                        TextField(
                            provider.id == "custom" || provider.id == "ollama" ? "Base URL (bắt buộc)" : "Base URL (tùy chọn)",
                            text: dictBinding(\.baseURLs, provider.id),
                            prompt: Text(provider.defaultBaseURL.isEmpty ? "https://your-server.com/v1" : provider.defaultBaseURL)
                        )
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        modelField(provider)
                    } header: {
                        HStack {
                            Label(provider.name, systemImage: provider.symbol)
                            Spacer()
                            Text(provider.isFreeTier ? "🆓 Miễn phí" : "💰 Trả phí")
                                .font(.caption)
                                .foregroundStyle(provider.isFreeTier ? .green : .secondary)
                        }
                    }
                }

                Section {
                    Text("API key chỉ được lưu trên thiết bị của bạn (UserDefaults), không gửi đi đâu khác ngoài nhà cung cấp AI bạn chọn.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cài đặt")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    // MARK: Components

    private func statusDot(_ provider: AIProvider) -> some View {
        Circle()
            .fill(settings.isConfigured(for: provider) ? Color.green : Color.gray.opacity(0.4))
            .frame(width: 10, height: 10)
    }

    private func modelField(_ provider: AIProvider) -> some View {
        HStack {
            TextField("Model", text: dictBinding(\.models, provider.id), prompt: Text(provider.defaultModel.isEmpty ? "vd: gpt-4o-mini" : provider.defaultModel))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !provider.commonModels.isEmpty {
                Menu {
                    ForEach(provider.commonModels, id: \.self) { model in
                        Button(model) {
                            settings.models[provider.id] = model
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func dictBinding(
        _ keyPath: ReferenceWritableKeyPath<SettingsStore, [String: String]>,
        _ providerID: String
    ) -> Binding<String> {
        Binding(
            get: { settings[keyPath: keyPath][providerID] ?? "" },
            set: { settings[keyPath: keyPath][providerID] = $0 }
        )
    }
}
