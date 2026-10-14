import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject private var conversations: ConversationStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if conversations.conversations.isEmpty {
                    ContentUnavailableView("Chưa có chat nào", systemImage: "bubble.left.and.text.bubble.right")
                } else {
                    conversationList
                }
            }
            .navigationTitle("Lịch sử chat")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        conversations.newConversation(providerID: conversations.current?.providerID ?? Providers.all[0].id)
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(conversations.conversations) { conversation in
                Button {
                    conversations.select(conversation.id)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: Providers.byID(conversation.providerID).symbol)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(conversation.title)
                                .lineLimit(1)
                                .font(.body)
                                .foregroundColor(.primary)
                            HStack {
                                Text(Providers.byID(conversation.providerID).name)
                                    .font(.caption)
                                Spacer()
                                Text(conversation.createdAt, style: .relative)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                        if conversation.id == conversations.currentID {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .onDelete { conversations.delete(at: $0) }
        }
    }
}
