import Foundation

enum AIServiceError: LocalizedError {
    case missingAPIKey(String)
    case badURL
    case httpError(Int, String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Chưa nhập API key cho \(provider). Mở ⚙️ Cài đặt để nhập."
        case .badURL:
            return "Base URL không hợp lệ. Kiểm tra lại trong ⚙️ Cài đặt."
        case .httpError(let code, let message):
            var hint: String
            switch code {
            case 401: hint = "API key sai hoặc hết hạn — kiểm tra lại trong ⚙️ Cài đặt (bấm 'Kiểm tra' để thử ngay)."
            case 402: hint = "Tài khoản chưa có tiền — AI này trả phí, cần nạp tiền hoặc dùng AI miễn phí (Gemini/Groq/OpenRouter)."
            case 403: hint = "Key bị từ chối quyền truy cập — kiểm tra key còn hoạt động không."
            case 429: hint = "Vượt giới hạn miễn phí — chờ 1-2 phút rồi gửi lại (không mất gì)."
            case 404: hint = "Model không tồn tại — app sẽ tự chuyển về model mặc định."
            default: hint = ""
            }
            let lowerCheck = message.lowercased()
            if code == 400 && lowerCheck.contains("api key") && (lowerCheck.contains("not valid") || lowerCheck.contains("invalid") || lowerCheck.contains("expired")) {
                hint = "API key không hợp lệ — lấy key đúng từ trang chủ của AI đó và dán lại trong ⚙️ Cài đặt (bấm 'Kiểm tra' để thử ngay)."
            }
            var extra = ""
            let lower = message.lowercased()
            if lower.contains("image") || lower.contains("vision") || lower.contains("multimodal") || lower.contains("content part") || lower.contains("image_url") {
                extra = " Model này không nhận được ảnh — app sẽ tự đổi model đọc ảnh, hoặc gửi lại không kèm ảnh."
            }
            let detail = message.isEmpty ? "" : " Chi tiết: \(message)"
            return "Lỗi HTTP \(code). \(hint)\(extra)\(detail)"
        case .server(let message):
            return "Lỗi từ server: \(message)"
        }
    }
}

/// Gọi API của các AI provider với streaming (SSE).
enum AIService {

    // MARK: - Public

    static func stream(
        provider: AIProvider,
        baseURL customBaseURL: String,
        model: String,
        apiKey: String,
        systemPrompt: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        let base = normalizedBase(customBaseURL, provider)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch provider.apiStyle {
                    case .openai:
                        try await streamOpenAI(base, provider, model, apiKey, systemPrompt, history, continuation)
                    case .anthropic:
                        try await streamAnthropic(base, provider, model, apiKey, systemPrompt, history, continuation)
                    case .gemini:
                        try await streamGemini(base, provider, model, apiKey, systemPrompt, history, continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Kiểm tra key + base URL có hoạt động không. Trả về (ok, thông báo).
    static func verifyKey(
        provider: AIProvider,
        baseURL customBaseURL: String,
        apiKey: String
    ) async -> (ok: Bool, message: String) {
        let base = normalizedBase(customBaseURL, provider)

        let urlString: String
        var request: URLRequest
        switch provider.apiStyle {
        case .openai:
            guard let url = URL(string: base + "/models") else {
                return (false, "Base URL không hợp lệ: \(base)")
            }
            request = URLRequest(url: url)
            request.timeoutInterval = 30
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            urlString = base + "/models"
        case .anthropic:
            guard let url = URL(string: base + "/v1/models") else {
                return (false, "Base URL không hợp lệ: \(base)")
            }
            request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            urlString = base + "/v1/models"
        case .gemini:
            guard let url = URL(string: base + "/v1beta/models") else {
                return (false, "Base URL không hợp lệ: \(base)")
            }
            request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            urlString = base + "/v1beta/models"
        }
        _ = urlString

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = String(data: data.prefix(600), encoding: .utf8) ?? ""
                let error = AIServiceError.httpError(status, body)
                return (false, error.errorDescription ?? "Lỗi HTTP \(status)")
            }
            var count = 0
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let list = object["data"] as? [[String: Any]] { count = list.count }
                if let list = object["models"] as? [[String: Any]] { count = list.count }
            }
            return (true, "Kết nối OK\(count > 0 ? " — \(count) model khả dụng" : "").")
        } catch {
            return (false, "Không kết nối được \(base) — kiểm tra mạng hoặc Base URL. (\(error.localizedDescription))")
        }
    }

    // MARK: - OpenAI-compatible (OpenAI, Groq, DeepSeek, OpenRouter, Ollama, custom)

    private static func streamOpenAI(
        _ base: String,
        _ provider: AIProvider,
        _ model: String,
        _ apiKey: String,
        _ systemPrompt: String,
        _ history: [ChatMessage],
        _ continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let url = URL(string: base + "/chat/completions") else {
            throw AIServiceError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var messages: [[String: Any]] = []
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        for message in history where message.role != .system {
            messages.append(["role": message.role.rawValue, "content": openAIContent(message)])
        }

        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["model": model, "messages": messages, "stream": true]
        )

        for try await data in ssePayloads(from: request) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let err = object["error"] as? [String: Any],
               let msg = (err["message"] as? String) ?? (err["error"] as? String) {
                throw AIServiceError.server(msg)
            }
            guard let choices = object["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let text = delta["content"] as? String,
                  !text.isEmpty else { continue }
            continuation.yield(text)
        }
    }

    // MARK: - Anthropic (Claude)

    private static func streamAnthropic(
        _ base: String,
        _ provider: AIProvider,
        _ model: String,
        _ apiKey: String,
        _ systemPrompt: String,
        _ history: [ChatMessage],
        _ continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        if apiKey.isEmpty {
            throw AIServiceError.missingAPIKey(provider.name)
        }
        guard let url = URL(string: base + "/v1/messages") else {
            throw AIServiceError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var messages: [[String: Any]] = []
        for message in history where message.role != .system {
            messages.append(["role": message.role.rawValue, "content": anthropicContent(message)])
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "stream": true,
            "messages": messages,
        ]
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            body["system"] = system
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        for try await data in ssePayloads(from: request) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if object["type"] as? String == "error" {
                let err = object["error"] as? [String: Any]
                let msg = (err?["message"] as? String) ?? "Lỗi không xác định"
                throw AIServiceError.server(msg)
            }
            guard object["type"] as? String == "content_block_delta",
                  let delta = object["delta"] as? [String: Any],
                  let text = delta["text"] as? String,
                  !text.isEmpty else { continue }
            continuation.yield(text)
        }
    }

    // MARK: - Google Gemini

    private static func streamGemini(
        _ base: String,
        _ provider: AIProvider,
        _ model: String,
        _ apiKey: String,
        _ systemPrompt: String,
        _ history: [ChatMessage],
        _ continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        if apiKey.isEmpty {
            throw AIServiceError.missingAPIKey(provider.name)
        }
        let urlString = base + "/v1beta/models/\(model):streamGenerateContent?alt=sse"
        guard let url = URL(string: urlString) else {
            throw AIServiceError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        var contents: [[String: Any]] = []
        for message in history where message.role != .system {
            let role = message.role == .assistant ? "model" : "user"
            contents.append(["role": role, "parts": geminiParts(message)])
        }

        var body: [String: Any] = ["contents": contents]
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        for try await data in ssePayloads(from: request) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let err = object["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw AIServiceError.server(msg)
            }
            guard let candidates = object["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty {
                continuation.yield(text)
            }
        }
    }

    // MARK: - Helpers

    /// Nội dung user message cho OpenAI-compatible API (hỗ trợ ảnh dạng data URL).
    private static func openAIContent(_ message: ChatMessage) -> Any {
        if let images = message.images, !images.isEmpty {
            var content: [[String: Any]] = [["type": "text", "text": message.text]]
            for image in images {
                content.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(image.mimeType);base64,\(image.base64)"]
                ])
            }
            return content
        }
        return message.text
    }

    /// Nội dung cho Anthropic API (ảnh dạng base64 source).
    private static func anthropicContent(_ message: ChatMessage) -> Any {
        if let images = message.images, !images.isEmpty {
            var content: [[String: Any]] = [["type": "text", "text": message.text]]
            for image in images {
                content.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": image.mimeType, "data": image.base64]
                ])
            }
            return content
        }
        return message.text
    }

    /// Parts cho Gemini API (ảnh dạng inline_data).
    private static func geminiParts(_ message: ChatMessage) -> [[String: Any]] {
        var parts: [[String: Any]] = [["text": message.text]]
        if let images = message.images {
            for image in images {
                parts.append([
                    "inline_data": ["mime_type": image.mimeType, "data": image.base64]
                ])
            }
        }
        return parts
    }

    /// Base URL dùng thật: tùy chỉnh từ Cài đặt nếu có, không thì dùng mặc định; bỏ dấu "/" cuối.
    private static func normalizedBase(_ customBaseURL: String, _ provider: AIProvider) -> String {
        var base = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            base = provider.defaultBaseURL
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    /// Thực hiện request và stream về từng payload JSON trong luồng SSE (`data: {...}`).
    private static func ssePayloads(from request: URLRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIServiceError.badURL
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line + "\n"
                            if body.count > 2000 { break }
                        }
                        throw AIServiceError.httpError(http.statusCode, body.isEmpty ? "(không có chi tiết)" : body)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if let data = payload.data(using: .utf8) {
                            continuation.yield(data)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
