import Foundation

/// Ollama local LLM provider
public final class OllamaProvider: LLMProvider, @unchecked Sendable {
    private let model: String
    private let endpoint: String

    public init(model: String = "llama3", endpoint: String = "http://localhost:11434") {
        self.model = model
        self.endpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    public func complete(messages: [LLMMessage]) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": false
        ]

        guard let url = URL(string: "\(endpoint)/api/chat") else {
            throw LLMError.networkError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120 // Ollama can be slow

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.serverError("Ollama request failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.emptyResponse
        }
        return content
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
}
