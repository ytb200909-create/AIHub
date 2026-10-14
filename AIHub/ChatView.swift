import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject private var conversations: ConversationStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var input = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var showHistory = false
    @State private var showSettings = false

    // Đính kèm
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var pendingImages: [ImageAttachment] = []
    @State private var pendingFileName: String?
    @State private var pendingFileContent: String?
    @State private var showFileImporter = false
    @State private var importError: String?

    private var conversation: Conversation? {
        conversations.current
    }

    private var provider: AIProvider {
        Providers.byID(conversation?.providerID ?? Providers.all[0].id)
    }

    private var hasPendingAttachments: Bool {
        !pendingImages.isEmpty || pendingFileContent != nil
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
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                handleFile(at: url)
            }
        }
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items.prefix(4) {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        addImage(from: data)
                    }
                }
                photoSelection = []
            }
        }
        .alert("Không đọc được file", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "")
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
                pendingImages = []
                pendingFileName = nil
                pendingFileContent = nil
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
                            Text("Nhập câu hỏi, hoặc gửi 📷 ảnh / 📎 file để AI phân tích.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
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

    // MARK: Attachment strip

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pendingImages.indices, id: \.self) { index in
                    AttachmentThumb(base64: pendingImages[index].base64)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                pendingImages.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .offset(x: 4, y: -4)
                        }
                }

                if let fileName = pendingFileName {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Color.accentColor)
                        Text(fileName)
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            pendingFileName = nil
                            pendingFileContent = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 76)
    }

    // MARK: Input bar

    private func inputBar(_ conversation: Conversation) -> some View {
        VStack(spacing: 6) {
            if hasPendingAttachments {
                attachmentStrip
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }

                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }

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
                    .disabled(trimmedInput.isEmpty && !hasPendingAttachments)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Attachments handling

    private func addImage(from data: Data) {
        guard pendingImages.count < 4, let image = UIImage(data: data) else { return }
        let maxDimension: CGFloat = 1280
        let size = image.size
        let scaleFactor = min(1, maxDimension / max(size.width, size.height))
        var resized = image
        if scaleFactor < 1 {
            let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else { return }
        pendingImages.append(
            ImageAttachment(base64: jpeg.base64EncodedString(), mimeType: "image/jpeg")
        )
    }

    private func handleFile(at url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        guard let data = try? Data(contentsOf: url) else {
            importError = "Không đọc được nội dung file \(fileName)."
            return
        }

        // Ảnh trong Files → thêm như ảnh đính kèm
        if ["png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "bmp", "tiff"].contains(ext),
           UIImage(data: data) != nil {
            addImage(from: data)
            return
        }

        // PDF → trích xuất text bằng PDFKit
        if ext == "pdf" {
            guard let document = PDFDocument(data: data) else {
                importError = "File PDF bị hỏng hoặc không đọc được."
                return
            }
            var text = ""
            for pageIndex in 0..<min(document.pageCount, 40) {
                if let page = document.page(at: pageIndex), let pageText = page.string {
                    text += pageText + "\n"
                }
                if text.count > 15000 { break }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                importError = "Không trích xuất được chữ từ PDF này (có thể là file scan ảnh)."
                return
            }
            pendingFileContent = String(trimmed.prefix(15000))
            pendingFileName = fileName
            return
        }

        // File văn bản
        if let content = String(data: data, encoding: .utf8) {
            pendingFileContent = String(content.prefix(15000))
            pendingFileName = fileName
        } else {
            importError = "Chưa hỗ trợ đọc file này (chỉ hỗ trợ: ảnh, PDF, file văn bản)."
        }
    }

    // MARK: Sending

    private func send(to conversation: Conversation) {
        let hasImages = !pendingImages.isEmpty
        let hasFile = pendingFileContent != nil
        let text = trimmedInput
        guard !text.isEmpty || hasImages || hasFile, !isStreaming else { return }
        input = ""

        var finalText = text
        if let fileName = pendingFileName, let content = pendingFileContent {
            if !finalText.isEmpty { finalText += "\n\n" }
            finalText += "📎 Nội dung file \"\(fileName)\":\n\(content)"
        }
        if finalText.isEmpty { finalText = "(xem ảnh đính kèm)" }

        let selectedProvider = Providers.byID(conversation.providerID)
        let apiKey = settings.apiKey(for: selectedProvider)

        if selectedProvider.needsAPIKey && apiKey.isEmpty {
            conversations.appendMessage(
                conversation.id,
                ChatMessage(role: .assistant, text: "⚠️ Chưa nhập API key cho \(selectedProvider.name). Mở ⚙️ Cài đặt để nhập key.")
            )
            return
        }

        let userMessage = ChatMessage(
            role: .user,
            text: finalText,
            images: hasImages ? pendingImages : nil
        )
        conversations.appendMessage(conversation.id, userMessage)
        let history = conversations.current?.messages ?? []
        conversations.appendAssistantPlaceholder(conversation.id)

        let conversationID = conversation.id
        let model = settings.model(for: selectedProvider)
        let systemPrompt = settings.systemPrompt
        isStreaming = true

        pendingImages = []
        pendingFileName = nil
        pendingFileContent = nil

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

// MARK: - Thumbnails

struct AttachmentThumb: View {
    let base64: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(uiColor: .tertiarySystemFill)
            }
        }
        .onAppear {
            if image == nil, let data = Data(base64Encoded: base64) {
                image = UIImage(data: data)
            }
        }
    }
}

// MARK: - Message bubble

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if let images = message.images, !images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(images.indices, id: \.self) { index in
                            AttachmentThumb(base64: images[index].base64)
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                if !message.text.isEmpty {
                    Text(message.text)
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
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
    }
}
