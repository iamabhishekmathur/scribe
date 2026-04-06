import Foundation

/// OpenAI-compatible API provider (works with OpenAI, Azure, any compatible endpoint)
public final class OpenAIProvider: LLMProvider, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let endpoint: String
    private let maxTokens: Int

    public var supportsVision: Bool {
        model.contains("gpt-4") || model.contains("vision")
    }

    public init(
        apiKey: String,
        model: String = "gpt-4o",
        endpoint: String = "https://api.openai.com/v1",
        maxTokens: Int = 4096
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.maxTokens = maxTokens
    }

    public func complete(messages: [LLMMessage]) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]

        let data = try await makeRequest(path: "/chat/completions", body: body)
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
        var msgs: [[String: Any]] = []
        for msg in messages {
            if msg.role == .user && msg == messages.last {
                msgs.append([
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": [
                            "url": "data:image/png;base64,\(imageData.base64EncodedString())"
                        ]],
                        ["type": "text", "text": msg.content]
                    ] as [[String: Any]]
                ])
            } else {
                msgs.append(["role": msg.role.rawValue, "content": msg.content])
            }
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": msgs
        ]
        let data = try await makeRequest(path: "/chat/completions", body: body)
        return try parseResponse(data)
    }

    private func makeRequest(path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(endpoint)\(path)") else {
            throw LLMError.networkError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.emptyResponse
        }
        return content
    }
}

/// Make LLMMessage Equatable for comparison in completeWithImage
extension LLMMessage: Equatable {
    public static func == (lhs: LLMMessage, rhs: LLMMessage) -> Bool {
        lhs.role == rhs.role && lhs.content == rhs.content
    }
}
