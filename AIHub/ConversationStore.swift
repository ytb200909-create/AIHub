import Foundation
import SwiftUI

/// Quản lý danh sách hội thoại, lưu ra file JSON trong Documents.
final class ConversationStore: ObservableObject {
    @Published var conversations: [Conversation] = [] { didSet { scheduleSave() } }
    @Published var currentID: UUID? { didSet { scheduleSave() } }

    private struct PersistedState: Codable {
        var conversations: [Conversation]
        var currentID: UUID?
    }

    private var saveTask: Task<Void, Never>?

    private var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("aihub-chats.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            conversations = state.conversations
            currentID = state.currentID
        }
        if conversations.isEmpty {
            newConversation(providerID: Providers.all[0].id)
        }
        if currentID == nil {
            currentID = conversations.first?.id
        }
    }

    // MARK: Persistence

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        let state = PersistedState(conversations: conversations, currentID: currentID)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Accessors

    var current: Conversation? {
        conversations.first { $0.id == currentID }
    }

    // MARK: Mutations

    func newConversation(providerID: String) {
        let conversation = Conversation(providerID: providerID)
        conversations.insert(conversation, at: 0)
        currentID = conversation.id
    }

    func select(_ id: UUID) {
        currentID = id
    }

    func setProvider(_ conversationID: UUID, _ providerID: String) {
        guard let index = indexOf(conversationID) else { return }
        conversations[index].providerID = providerID
    }

    func delete(_ conversationID: UUID) {
        conversations.removeAll { $0.id == conversationID }
        if currentID == conversationID {
            currentID = conversations.first?.id
        }
        if conversations.isEmpty {
            newConversation(providerID: Providers.all[0].id)
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { conversations[$0].id }
        ids.forEach { delete($0) }
    }

    func appendMessage(_ conversationID: UUID, _ message: ChatMessage) {
        guard let index = indexOf(conversationID) else { return }
        conversations[index].messages.append(message)
        if message.role == .user, conversations[index].messages.count == 1 {
            conversations[index].title = String(message.text.prefix(40))
        }
    }

    func appendAssistantPlaceholder(_ conversationID: UUID) {
        appendMessage(conversationID, ChatMessage(role: .assistant, text: ""))
    }

    /// Nối thêm text vào tin nhắn assistant cuối cùng (đang stream).
    func appendToLastAssistant(_ conversationID: UUID, text: String) {
        guard let index = indexOf(conversationID) else { return }
        guard let lastIndex = conversations[index].messages.indices.last,
              conversations[index].messages[lastIndex].role == .assistant else { return }
        conversations[index].messages[lastIndex].text += text
    }

    /// Xóa tin nhắn assistant cuối cùng (dùng cho "Tạo lại câu trả lời").
    func removeLastAssistant(_ conversationID: UUID) {
        guard let index = indexOf(conversationID),
              let lastIndex = conversations[index].messages.indices.last,
              conversations[index].messages[lastIndex].role == .assistant else { return }
        conversations[index].messages.remove(at: lastIndex)
    }

    /// Xóa tin nhắn có id cho trước và mọi tin nhắn sau nó (dùng cho "Sửa tin nhắn").
    func truncateAfterMessage(_ conversationID: UUID, _ messageID: UUID) {
        guard let index = indexOf(conversationID),
              let msgIndex = conversations[index].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[index].messages.removeSubrange(msgIndex...)
    }

    /// Xóa toàn bộ nội dung của một hội thoại.
    func clearMessages(_ conversationID: UUID) {
        guard let index = indexOf(conversationID) else { return }
        conversations[index].messages = []
        conversations[index].title = "Chat mới"
    }

    /// Ghi lỗi vào tin nhắn assistant cuối cùng.
    func appendError(_ conversationID: UUID, _ message: String) {
        guard let index = indexOf(conversationID) else { return }
        guard let lastIndex = conversations[index].messages.indices.last,
              conversations[index].messages[lastIndex].role == .assistant else { return }
        let prefix = conversations[index].messages[lastIndex].text.isEmpty ? "" : "\n\n"
        conversations[index].messages[lastIndex].text += prefix + message
    }

    private func indexOf(_ id: UUID) -> Array<Conversation>.Index? {
        conversations.firstIndex { $0.id == id }
    }
}
