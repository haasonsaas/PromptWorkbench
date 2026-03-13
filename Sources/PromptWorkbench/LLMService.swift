import Foundation

final class LLMService {
    static let shared = LLMService()
    private init() {}

    /// Multi-turn streaming with full message history.
    func stream(
        provider: LLMProvider,
        model: String,
        messages: [ChatMessage],
        temperature: Double,
        maxTokens: Int = 4096,
        onToken: @escaping (StreamToken) -> Void
    ) async throws {
        guard let apiKey = provider.apiKey, !apiKey.isEmpty else {
            throw LLMError.noAPIKey(provider)
        }

        let request = try buildRequest(
            provider: provider, model: model, messages: messages,
            temperature: temperature, maxTokens: maxTokens, apiKey: apiKey
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw LLMError.httpError(http.statusCode, body)
        }

        switch provider {
        case .anthropic:
            try await parseAnthropicSSE(bytes: bytes, onToken: onToken)
        case .openAI, .openRouter:
            try await parseOpenAISSE(bytes: bytes, onToken: onToken)
        }
    }

    /// Convenience: single-turn with system + user prompt.
    func stream(
        provider: LLMProvider,
        model: String,
        systemPrompt: String?,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int = 4096,
        onToken: @escaping (StreamToken) -> Void
    ) async throws {
        var msgs: [ChatMessage] = []
        if let sys = systemPrompt, !sys.isEmpty {
            msgs.append(ChatMessage(role: "system", content: sys))
        }
        msgs.append(ChatMessage(role: "user", content: userPrompt))
        try await stream(provider: provider, model: model, messages: msgs,
                         temperature: temperature, maxTokens: maxTokens, onToken: onToken)
    }

    // MARK: - Request Building

    private func buildRequest(
        provider: LLMProvider, model: String, messages: [ChatMessage],
        temperature: Double, maxTokens: Int, apiKey: String
    ) throws -> URLRequest {
        let url: URL
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: [String: Any]

        // Separate system from conversation messages
        let systemContent = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
        let conversationMsgs = messages.filter { $0.role != "system" }
        let apiMessages = conversationMsgs.map { ["role": $0.role, "content": $0.content] }

        switch provider {
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
            body = [
                "model": model,
                "max_tokens": maxTokens,
                "stream": true,
                "temperature": temperature,
                "messages": apiMessages,
            ]
            if !systemContent.isEmpty { body["system"] = systemContent }

        case .openAI:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
            headers["Authorization"] = "Bearer \(apiKey)"
            var allMessages: [[String: String]] = []
            if !systemContent.isEmpty {
                allMessages.append(["role": "system", "content": systemContent])
            }
            allMessages.append(contentsOf: apiMessages)
            body = [
                "model": model,
                "stream": true,
                "stream_options": ["include_usage": true],
                "temperature": temperature,
                "max_completion_tokens": maxTokens,
                "messages": allMessages,
            ]

        case .openRouter:
            url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            headers["Authorization"] = "Bearer \(apiKey)"
            headers["HTTP-Referer"] = "https://promptworkbench.local"
            headers["X-Title"] = "PromptWorkbench"
            var allMessages: [[String: String]] = []
            if !systemContent.isEmpty {
                allMessages.append(["role": "system", "content": systemContent])
            }
            allMessages.append(contentsOf: apiMessages)
            body = [
                "model": model,
                "stream": true,
                "temperature": temperature,
                "max_tokens": maxTokens,
                "messages": allMessages,
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - SSE Parsing

    private func parseAnthropicSSE(
        bytes: URLSession.AsyncBytes,
        onToken: @escaping (StreamToken) -> Void
    ) async throws {
        var inputTokens: Int?
        var outputTokens: Int?

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            switch type {
            case "message_start":
                if let msg = json["message"] as? [String: Any],
                   let usage = msg["usage"] as? [String: Any] {
                    inputTokens = usage["input_tokens"] as? Int
                }
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    onToken(StreamToken(text: text, inputTokens: nil, outputTokens: nil, done: false))
                }
            case "message_delta":
                if let usage = json["usage"] as? [String: Any] {
                    outputTokens = usage["output_tokens"] as? Int
                }
            case "message_stop":
                onToken(StreamToken(text: "", inputTokens: inputTokens, outputTokens: outputTokens, done: true))
            default:
                break
            }
        }
    }

    private func parseOpenAISSE(
        bytes: URLSession.AsyncBytes,
        onToken: @escaping (StreamToken) -> Void
    ) async throws {
        var inputTokens: Int?
        var outputTokens: Int?

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" {
                onToken(StreamToken(text: "", inputTokens: inputTokens, outputTokens: outputTokens, done: true))
                break
            }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let usage = json["usage"] as? [String: Any] {
                inputTokens = usage["prompt_tokens"] as? Int
                outputTokens = usage["completion_tokens"] as? Int
            }
            if let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                onToken(StreamToken(text: content, inputTokens: nil, outputTokens: nil, done: false))
            }
        }
    }
}

enum LLMError: LocalizedError {
    case noAPIKey(LLMProvider)
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey(let p): return "No API key set for \(p.rawValue). Configure in Settings."
        case .invalidResponse: return "Invalid response from server."
        case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(500))"
        }
    }
}
