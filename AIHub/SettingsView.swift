import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var checkingProviderID: String?
    @State private var checkResults: [String: String] = [:]

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
                        checkRow(provider)
                        if hasAnyCustomValue(provider) {
                            resetRow(provider)
                        }
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

                Section {
                    VStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                        Text("AI Hub v1.0")
                            .font(.footnote.weight(.semibold))
                        Text("Thiết kế & phát triển bởi ThanhChech © 2026")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
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

    /// Nút kiểm tra key + kết nối của một AI.
    private func checkRow(_ provider: AIProvider) -> some View {
        HStack(spacing: 8) {
            Button {
                checkProvider(provider)
            } label: {
                HStack(spacing: 5) {
                    if checkingProviderID == provider.id {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.shield")
                            .font(.footnote)
                    }
                    Text("Kiểm tra")
                        .font(.footnote)
                }
            }
            .buttonStyle(.borderless)
            .disabled(checkingProviderID != nil)

            if let result = checkResults[provider.id] {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.hasPrefix("✅") ? Color.green : Color.red)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
    }

    private func checkProvider(_ provider: AIProvider) {
        checkingProviderID = provider.id
        checkResults[provider.id] = nil
        Task {
            let result = await AIService.verifyKey(
                provider: provider,
                baseURL: settings.baseURL(for: provider),
                apiKey: settings.apiKey(for: provider)
            )
            await MainActor.run {
                checkResults[provider.id] = (result.ok ? "✅ " : "❌ ") + result.message
                checkingProviderID = nil
            }
        }
    }

    /// Có lưu tùy chỉnh nào cho AI này không (key/URL/model cũ còn sót)?
    private func hasAnyCustomValue(_ provider: AIProvider) -> Bool {
        settings.apiKeys[provider.id]?.isEmpty == false
            || settings.baseURLs[provider.id]?.isEmpty == false
            || settings.models[provider.id]?.isEmpty == false
    }

    /// Xóa mọi tùy chỉnh của một AI về trạng thái mặc định sạch sẽ.
    private func resetRow(_ provider: AIProvider) -> some View {
        Button(role: .destructive) {
            settings.apiKeys.removeValue(forKey: provider.id)
            settings.baseURLs.removeValue(forKey: provider.id)
            settings.models.removeValue(forKey: provider.id)
            checkResults[provider.id] = nil
        } label: {
            Label("Xóa tùy chỉnh của AI này (về mặc định)", systemImage: "arrow.uturn.backward.circle")
                .font(.footnote)
        }
        .buttonStyle(.borderless)
    }

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
