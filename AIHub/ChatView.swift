import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import UIKit

struct ChatView: View {
    @EnvironmentObject private var conversations: ConversationStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var input = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var showSidebar = false
    @State private var showSettings = false

    // Đính kèm
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var pendingImages: [ImageAttachment] = []
    @State private var pendingFileName: String?
    @State private var pendingFileContent: String?
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var importError: String?
    @State private var isNearBottom = true
    @State private var showScrollButton = false

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
        ZStack {
            Group {
                if let conversation {
                    if conversation.messages.isEmpty {
                        // Màn hình chào kiểu ChatGPT: nội dung + ô nhập ở giữa màn hình
                        VStack(spacing: 0) {
                            Spacer()
                            emptyState
                            Spacer()
                            inputBar(conversation)
                            Text("AI Hub có thể mắc lỗi. Hãy kiểm tra các thông tin quan trọng.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                        }
                    } else {
                        VStack(spacing: 0) {
                            messageList(conversation)
                            inputBar(conversation)
                        }
                    }
                } else {
                    ContentUnavailableView("Chưa có chat nào", systemImage: "bubble.left.and.text.bubble.right")
                }
            }

            if showSidebar {
                sidebarOverlay
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                addImage(from: image)
            }
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

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showSettings = true
                } label: {
                    Label("Cài đặt", systemImage: "gearshape")
                }
                ShareLink(item: exportText) {
                    Label("Xuất chat ra văn bản", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    if let conversation {
                        conversations.clearMessages(conversation.id)
                    }
                } label: {
                    Label("Xóa nội dung chat này", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }

        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button {
                hideKeyboard()
            } label: {
                Label("Ẩn bàn phím", systemImage: "keyboard.chevron.compact.down")
            }
        }

        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                withAnimation(.easeOut(duration: 0.22)) { showSidebar = true }
            } label: {
                Image(systemName: "sidebar.left")
            }
        }
    }

    // MARK: Message list

    private func messageList(_ conversation: Conversation) -> some View {
        GeometryReader { viewport in
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if conversation.messages.isEmpty {
                        emptyState
                    }

                    ForEach(conversation.messages) { message in
                        MessageBubble(message: message, onEdit: message.role == .user ? {
                            conversations.truncateAfterMessage(conversation.id, message.id)
                            input = message.text
                        } : nil)
                            .id(message.id)
                    }

                    if !isStreaming,
                       let last = conversation.messages.last,
                       last.role == .assistant,
                       !last.text.isEmpty {
                        // Hàng hành động kiểu ChatGPT: copy + tạo lại, đặt dưới câu trả lời
                        HStack(spacing: 20) {
                            Button {
                                UIPasteboard.general.string = last.text
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            Button {
                                regenerate(conversation)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .padding(.leading, 36)
                    }

                    Color.clear.frame(height: 4).id("bottom-anchor")
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: ChatBottomGapKey.self,
                                    value: g.frame(in: .global).maxY - viewport.frame(in: .global).maxY
                                )
                            }
                        )
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded {
                hideKeyboard()
            })
            .overlay(alignment: .bottom) {
                if showScrollButton {
                    Button {
                        scrollToBottom(proxy, force: true)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.regularMaterial))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1)))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showScrollButton)
            .onPreferenceChange(ChatBottomGapKey.self) { gap in
                isNearBottom = gap < 120
                showScrollButton = gap > 100
            }
            .onChange(of: conversation.messages.last?.text ?? "") { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
        }
        }
    }

    // MARK: Empty state (màn hình chat mới, kiểu ChatGPT)

    private var suggestions: [(icon: String, title: String, prompt: String)] {
        [
            ("envelope", "Viết email", "Hãy giúp tôi viết một email chuyên nghiệp để…"),
            ("lightbulb", "Lên ý tưởng", "Cho tôi 5 ý tưởng về…"),
            ("book", "Giải thích dễ hiểu", "Giải thích cho tôi khái niệm… như giải thích cho trẻ 10 tuổi."),
            ("globe", "Dịch thuật", "Dịch đoạn văn sau sang tiếng Anh:…")
        ]
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.39, green: 0.24, blue: 0.92), Color(red: 0.16, green: 0.47, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 76, height: 76)
                Image(systemName: provider.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("Mình có thể giúp gì cho bạn?")
                    .font(.title3.weight(.semibold))
                Text("Hỏi bất cứ điều gì, hoặc gửi 📷 ảnh / 📎 file để AI phân tích.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(suggestions.indices, id: \.self) { index in
                    let s = suggestions[index]
                    Button {
                        input = s.prompt
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: s.icon)
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                            Text(s.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Sidebar (menu kéo ngang kiểu ChatGPT)

    private var sidebarOverlay: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { showSidebar = false }
                }
            SidebarDrawer(
                onClose: {
                    withAnimation(.easeOut(duration: 0.2)) { showSidebar = false }
                },
                onOpenSettings: {
                    withAnimation(.easeOut(duration: 0.2)) { showSidebar = false }
                    showSettings = true
                }
            )
            .transition(.move(edge: .leading))
        }
    }

    /// Chỉ tự cuộn khi người dùng đang ở gần cuối (kiểu ChatGPT), trừ khi ép buộc.
    private func scrollToBottom(_ proxy: ScrollViewProxy, force: Bool = false) {
        guard force || isNearBottom else { return }
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

            HStack(spacing: 8) {
                // Nút "+" gom tất cả kiểu đính kèm (kiểu ChatGPT)
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Thư viện ảnh", systemImage: "photo")
                    }
                    if isCameraAvailable {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Chụp ảnh", systemImage: "camera")
                        }
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Đính kèm file", systemImage: "paperclip")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }

                TextField("Hỏi bất cứ điều gì…", text: $input, axis: .vertical)
                    .lineLimit(1...6)

                if isStreaming {
                    Button {
                        stopStreaming()
                    } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                            .frame(width: 12, height: 12)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(uiColor: .label)))
                    }
                } else {
                    Button {
                        send(to: conversation)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(canSend ? Color(uiColor: .systemBackground) : Color(uiColor: .systemGray3))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(canSend ? Color(uiColor: .label) : Color(uiColor: .systemGray5)))
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoSelection,
            maxSelectionCount: 4,
            matching: .images
        )
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedInput.isEmpty || hasPendingAttachments
    }

    private var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    // MARK: Attachments handling

    private func addImage(from data: Data) {
        guard pendingImages.count < 4, let image = UIImage(data: data) else { return }
        addImage(from: image)
    }

    private func addImage(from image: UIImage) {
        guard pendingImages.count < 4 else { return }
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

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        pendingImages = []
        pendingFileName = nil
        pendingFileContent = nil

        streamResponse(to: conversation, history: history, provider: selectedProvider, apiKey: apiKey)
    }

    /// Gửi lịch sử hội thoại đến AI và stream câu trả lời vào placeholder cuối.
    private func streamResponse(to conversation: Conversation, history: [ChatMessage], provider: AIProvider, apiKey: String) {
        conversations.appendAssistantPlaceholder(conversation.id)

        let conversationID = conversation.id
        let model = settings.model(for: provider)
        let systemPrompt = settings.systemPrompt
        isStreaming = true

        streamTask = Task {
            do {
                let stream = AIService.stream(
                    provider: provider,
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

    /// Xóa câu trả lời cuối và gọi lại AI với cùng ngữ cảnh.
    private func regenerate(_ conversation: Conversation) {
        guard !isStreaming else { return }
        let selectedProvider = Providers.byID(conversation.providerID)
        let apiKey = settings.apiKey(for: selectedProvider)
        guard !selectedProvider.needsAPIKey || !apiKey.isEmpty else { return }

        conversations.removeLastAssistant(conversation.id)
        let history = conversations.current?.messages ?? []
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        streamResponse(to: conversation, history: history, provider: selectedProvider, apiKey: apiKey)
    }

    private var exportText: String {
        guard let conversation else { return "" }
        var lines = ["# \(conversation.title) — AI Hub (ThanhChech)", ""]
        for message in conversation.messages {
            let who = message.role == .user ? "Bạn" : "AI"
            lines.append("\(who): \(message.text)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        conversations.saveNow()
    }
}

// MARK: - Scroll tracking

/// Khoảng cách từ đáy nội dung chat đến đáy màn hình (dương = đã cuộn lên trên).
struct ChatBottomGapKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
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

// MARK: - Message bubble (kiểu ChatGPT)

struct MessageBubble: View {
    let message: ChatMessage
    var onEdit: (() -> Void)? = nil

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if isUser {
            HStack(alignment: .bottom) {
                Spacer(minLength: 56)
                VStack(alignment: .trailing, spacing: 6) {
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
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AnyShapeStyle(Color(uiColor: .secondarySystemBackground)))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: {
                        Label("Copy tin nhắn", systemImage: "doc.on.doc")
                    }
                    if let onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("Sửa tin nhắn", systemImage: "pencil")
                        }
                    }
                }
            }
        } else {
            // Trả lời của AI: avatar tròn + chữ trải rộng toàn chiều rộng (kiểu ChatGPT)
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.39, green: 0.24, blue: 0.92), Color(red: 0.16, green: 0.47, blue: 1.0)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    if let images = message.images, !images.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(images.indices, id: \.self) { index in
                                AttachmentThumb(base64: images[index].base64)
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }

                    if message.text.isEmpty {
                        TypingIndicator()
                    } else {
                        MarkdownContentView(text: message.text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label("Copy câu trả lời", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

// MARK: - Typing indicator (3 chấm nhấp nháy)

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(animating ? 1.0 : 0.55)
                    .opacity(animating ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(index) * 0.18),
                        value: animating
                    )
            }
        }
        .padding(.vertical, 8)
        .onAppear { animating = true }
    }
}

// MARK: - Camera picker

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Markdown rendering

struct MarkdownSegment: Identifiable {
    let id: Int
    let isCode: Bool
    let content: String
}

struct MarkdownContentView: View {
    let text: String

    var body: some View {
        let segments = Self.splitFences(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                if segment.isCode {
                    CodeBlockView(code: segment.content)
                } else if let rendered = Self.inline(segment.content) {
                    rendered
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static func inline(_ content: String) -> Text? {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: content, options: options) else {
            return Text(content)
        }
        return Text(attributed)
    }

    static func splitFences(_ text: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        var plain = ""
        var codeLines: [String] = []
        var inCode = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineText = String(line)
            if lineText.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    segments.append(MarkdownSegment(id: segments.count, isCode: true, content: codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCode = false
                } else {
                    if !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append(MarkdownSegment(id: segments.count, isCode: false, content: plain))
                    }
                    plain = ""
                    inCode = true
                }
            } else if inCode {
                codeLines.append(lineText)
            } else {
                plain += lineText + "\n"
            }
        }

        if inCode, !codeLines.isEmpty {
            segments.append(MarkdownSegment(id: segments.count, isCode: true, content: codeLines.joined(separator: "\n")))
        } else if !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(MarkdownSegment(id: segments.count, isCode: false, content: plain))
        }
        return segments
    }
}

// MARK: - Code block

struct CodeBlockView: View {
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CODE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "Đã copy" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(Color(red: 0.11, green: 0.12, blue: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Sidebar drawer (kiểu ChatGPT)

struct SidebarDrawer: View {
    @EnvironmentObject private var conversations: ConversationStore
    var onClose: () -> Void
    var onOpenSettings: () -> Void

    @State private var search = ""

    private var filtered: [Conversation] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return conversations.conversations }
        return conversations.conversations.filter { $0.title.lowercased().contains(term) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                conversations.newConversation(providerID: conversations.current?.providerID ?? Providers.all[0].id)
                onClose()
            } label: {
                Label("Chat mới", systemImage: "plus.message")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Tìm kiếm chat", text: $search)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            List {
                ForEach(filtered) { conversation in
                    Button {
                        conversations.select(conversation.id)
                        onClose()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conversation.title)
                                .lineLimit(1)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Text(Providers.byID(conversation.providerID).name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(
                        conversation.id == conversations.currentID
                            ? Color(uiColor: .secondarySystemBackground)
                            : Color.clear
                    )
                }
                .onDelete { conversations.delete(at: $0) }
            }
            .listStyle(.plain)

            Divider()
            Button {
                onOpenSettings()
            } label: {
                Label("Cài đặt", systemImage: "gearshape")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .frame(width: min(320, UIScreen.main.bounds.width * 0.82))
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Keyboard helper

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
