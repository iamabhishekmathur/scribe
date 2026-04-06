import Foundation

/// Anthropic Claude API provider
public final class ClaudeProvider: LLMProvider, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let maxTokens: Int

    public var supportsVision: Bool { true }

    public init(apiKey: String, model: String = "claude-sonnet-4-20250514", maxTokens: Int = 4096) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
    }

    public func complete(messages: [LLMMessage]) async throws -> String {
        let (systemMsg, userMessages) = splitSystem(messages)
        let body = buildRequestBody(system: systemMsg, messages: userMessages)
        let data = try await makeRequest(body: body)
        return try parseResponse(data)
    }

    public func stream(messages: [LLMMessage]) -> AsyncStream<LLMStreamChunk> {
        AsyncStream { continuation in
            Task {
                do {
                    let result = try await self.complete(messages: messages)
                    continuation.yield(LLMStreamChunk(text: result, isComplete: true))
                } catch {
                    continuation.yield(LLMStreamChunk(text: "Error: \(error.localizedDescription)", isComplete: true))
                }
                continuation.finish()
            }
        }
    }

    public func completeWithImage(messages: [LLMMessage], imageData: Data) async throws -> String {
        let (systemMsg, userMessages) = splitSystem(messages)
        var body = buildRequestBody(system: systemMsg, messages: userMessages)

        // Replace last user message content with multimodal content
        if var msgs = body["messages"] as? [[String: Any]], !msgs.isEmpty {
            let lastIdx = msgs.count - 1
            let lastText = (msgs[lastIdx]["content"] as? String) ?? ""
            msgs[lastIdx]["content"] = [
                ["type": "image", "source": [
                    "type": "base64",
                    "media_type": "image/png",
                    "data": imageData.base64EncodedString()
                ]],
                ["type": "text", "text": lastText]
            ] as [[String: Any]]
            body["messages"] = msgs
        }

        let data = try await makeRequest(body: body)
        return try parseResponse(data)
    }

    // MARK: - Helpers

    private func splitSystem(_ messages: [LLMMessage]) -> (String?, [LLMMessage]) {
        var system: String?
        var rest: [LLMMessage] = []
        for msg in messages {
            if msg.role == .system { system = msg.content }
            else { rest.append(msg) }
        }
        return (system, rest)
    }

    private func buildRequestBody(system: String?, messages: [LLMMessage]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]
        if let system { body["system"] = system }
        return body
    }

    private func makeRequest(body: [String: Any]) async throws -> Data {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.networkError("Invalid response")
        }
        switch http.statusCode {
        case 200: return data
        case 401: throw LLMError.invalidAPIKey
        case 429: throw LLMError.rateLimited
        default: throw LLMError.serverError("HTTP \(http.statusCode)")
        }
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw LLMError.emptyResponse
        }
        return text
    }
}
