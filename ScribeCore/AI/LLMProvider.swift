import Foundation

/// A message in a chat conversation with an LLM
public struct LLMMessage: Sendable, Codable {
    public let role: Role
    public let content: String

    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
    }

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// A streaming chunk from an LLM response
public struct LLMStreamChunk: Sendable {
    public let text: String
    public let isComplete: Bool

    public init(text: String, isComplete: Bool = false) {
        self.text = text
        self.isComplete = isComplete
    }
}

/// Protocol for all LLM providers
public protocol LLMProvider: AnyObject, Sendable {
    /// Send messages and get a complete response
    func complete(messages: [LLMMessage]) async throws -> String

    /// Send messages and get a streaming response
    func stream(messages: [LLMMessage]) -> AsyncStream<LLMStreamChunk>

    /// Whether this provider supports vision (image input)
    var supportsVision: Bool { get }

    /// Send messages with an image for vision analysis
    func completeWithImage(messages: [LLMMessage], imageData: Data) async throws -> String
}

/// Default implementation for providers that don't support vision
extension LLMProvider {
    public var supportsVision: Bool { false }
    public func completeWithImage(messages: [LLMMessage], imageData: Data) async throws -> String {
        throw LLMError.visionNotSupported
    }
}

public enum LLMError: Error, LocalizedError {
    case invalidAPIKey
    case rateLimited
    case serverError(String)
    case networkError(String)
    case visionNotSupported
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "Invalid API key"
        case .rateLimited: return "Rate limited"
        case .serverError(let msg): return "Server error: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .visionNotSupported: return "Vision not supported by this provider"
        case .emptyResponse: return "Empty response from LLM"
        }
    }
}
