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
                LazyVStack(spacing: 16) {
                    if conversation.messages.isEmpty {
                        emptyState
                    }

                    ForEach(conversation.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    Color.clear.frame(height: 4).id("bottom-anchor")
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
            .onChange(of: conversation.messages.last?.text ?? "") { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                scrollToBottom(proxy)
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
            .padding(.top, 46)

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

            Spacer(minLength: 0)

            Text("AI Hub — bởi ThanhChech © 2026")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
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
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                TextField("Hỏi bất cứ điều gì…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 6)

                if isStreaming {
                    Button {
                        stopStreaming()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.red))
                    }
                } else {
                    Button {
                        send(to: conversation)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(canSend ? Color.accentColor : Color(uiColor: .systemGray4)))
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedInput.isEmpty || hasPendingAttachments
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

// MARK: - Message bubble (kiểu ChatGPT)

struct MessageBubble: View {
    let message: ChatMessage

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
                        Text("Đang soạn…")
                            .foregroundStyle(.secondary)
                            .font(.body)
                            .italic()
                    } else {
                        MarkdownContentView(text: message.text)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Keyboard helper

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
