import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var conversations: ConversationStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var input = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var showHistory = false
    @State private var showSettings = false

    private var conversation: Conversation? {
        conversations.current
    }

    private var provider: AIProvider {
        Providers.byID(conversation?.providerID ?? Providers.all[0].id)
    }

    var body: some View {
        Group {
            if let conversation {
                VStack(spacing: 0) {
                    messageList(conversation)
                    inputBar(conversation)
                }
            } else {
                ContentUnavailableView("Chưa có chat nào", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showHistory) {
            ConversationListView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Menu {
                ForEach(Providers.all) { p in
                    Button {
                        if let conversation {
                            conversations.setProvider(conversation.id, p.id)
                        }
                    } label: {
                        Label((p.id == provider.id ? "✓  " : "") + p.name, systemImage: p.symbol)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: provider.symbol)
                        .font(.footnote)
                    Text(provider.name)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                conversations.newConversation(providerID: provider.id)
            } label: {
                Image(systemName: "plus.message")
            }
        }

        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
    }

    // MARK: Message list

    private func messageList(_ conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if conversation.messages.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: provider.symbol)
                                .font(.system(size: 44))
                                .foregroundStyle(Color.accentColor)
                            Text("Xin chào! Mình là \(provider.name).")
                                .font(.headline)
                            Text("Hãy nhập câu hỏi bên dưới để bắt đầu.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 80)
                    }

                    ForEach(conversation.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    Color.clear.frame(height: 4).id("bottom-anchor")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .onChange(of: conversation.messages.last?.text ?? "") { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
    }

    // MARK: Input bar

    private func inputBar(_ conversation: Conversation) -> some View {
        HStack(spacing: 8) {
            TextField("Nhập tin nhắn…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

            if isStreaming {
                Button {
                    stopStreaming()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            } else {
                Button {
                    send(to: conversation)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(trimmedInput.isEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Sending

    private func send(to conversation: Conversation) {
        let text = trimmedInput
        guard !text.isEmpty, !isStreaming else { return }
        input = ""

        let selectedProvider = Providers.byID(conversation.providerID)
        let apiKey = settings.apiKey(for: selectedProvider)

        if selectedProvider.needsAPIKey && apiKey.isEmpty {
            conversations.appendMessage(
                conversation.id,
                ChatMessage(role: .assistant, text: "⚠️ Chưa nhập API key cho \(selectedProvider.name). Mở ⚙️ Cài đặt để nhập key.")
            )
            return
        }

        conversations.appendMessage(conversation.id, ChatMessage(role: .user, text: text))
        let history = conversations.current?.messages ?? []
        conversations.appendAssistantPlaceholder(conversation.id)

        let conversationID = conversation.id
        let model = settings.model(for: selectedProvider)
        let systemPrompt = settings.systemPrompt
        isStreaming = true

        streamTask = Task {
            do {
                let stream = AIService.stream(
                    provider: selectedProvider,
                    model: model,
                    apiKey: apiKey,
                    systemPrompt: systemPrompt,
                    history: history
                )
                for try await chunk in stream {
                    conversations.appendToLastAssistant(conversationID, text: chunk)
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                conversations.appendError(conversationID, "⚠️ \(message)")
            }
            isStreaming = false
            conversations.saveNow()
        }
    }

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        conversations.saveNow()
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 48) }
            Text(message.text.isEmpty ? "…" : message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    isUser
                        ? AnyShapeStyle(Color.accentColor.opacity(0.9))
                        : AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                )
                .foregroundColor(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer(minLength: 48) }
        }
    }
}
