import Foundation

/// A single transcription result segment
public struct TranscriptionResult: Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let speaker: String?
    public let speakerIndex: Int?
    public let confidence: Double?
    public let isFinal: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        speaker: String? = nil,
        speakerIndex: Int? = nil,
        confidence: Double? = nil,
        isFinal: Bool = true
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
        self.speakerIndex = speakerIndex
        self.confidence = confidence
        self.isFinal = isFinal
    }
}

/// Protocol for all transcription providers (Deepgram, AssemblyAI, OpenAI Whisper).
public protocol TranscriptionProvider: AnyObject, Sendable {
    /// Connect to the transcription service
    func connect() async throws

    /// Send raw PCM audio data (16kHz mono Float32) for transcription
    func sendAudio(_ data: Data) async throws

    /// Stream of transcription results
    var results: AsyncStream<TranscriptionResult> { get }

    /// Disconnect from the service
    func disconnect() async

    /// Whether currently connected
    var isConnected: Bool { get }
}

/// Errors from transcription providers
public enum TranscriptionError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case invalidAPIKey
    case rateLimited
    case serverError(String)
    case encodingError

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to transcription service"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .invalidAPIKey: return "Invalid API key"
        case .rateLimited: return "Rate limited by transcription service"
        case .serverError(let msg): return "Server error: \(msg)"
        case .encodingError: return "Failed to encode audio data"
        }
    }
}
