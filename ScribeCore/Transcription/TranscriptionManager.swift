@preconcurrency import AVFoundation
import Foundation

/// Bridges audio capture to the active transcription provider.
/// Converts PCM buffers to raw data, sends to provider, writes results to DB.
public final class TranscriptionManager: @unchecked Sendable {
    private var provider: (any TranscriptionProvider)?
    private var processingTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var _isActive = false

    public var isActive: Bool { _isActive }

    public init() {}

    /// Start transcription for a meeting using the given provider and audio stream.
    public func start(
        provider: any TranscriptionProvider,
        audioStream: sending AsyncStream<AVAudioPCMBuffer>,
        meetingId: UUID
    ) async throws {
        guard !_isActive else { return }

        self.provider = provider
        try await provider.connect()
        _isActive = true

        let store = MeetingStore.shared

        // Process incoming audio — convert buffers to raw data and send
        processingTask = Task.detached {
            for await buffer in audioStream {
                guard !Task.isCancelled else { break }
                if let data = Self.bufferToData(buffer) {
                    try? await provider.sendAudio(data)
                }
            }
        }

        // Process transcription results — write to DB
        resultsTask = Task.detached {
            for await result in provider.results {
                guard !Task.isCancelled else { break }
                if result.isFinal {
                    let segment = TranscriptSegment(
                        meetingId: meetingId,
                        speaker: result.speaker,
                        speakerIndex: result.speakerIndex,
                        text: result.text,
                        startTime: result.startTime,
                        endTime: result.endTime,
                        confidence: result.confidence,
                        isFinal: result.isFinal
                    )
                    try? await store.addTranscriptSegment(segment)
                }
            }
        }
    }

    /// Stop transcription
    public func stop() async {
        processingTask?.cancel()
        resultsTask?.cancel()
        processingTask = nil
        resultsTask = nil
        await provider?.disconnect()
        provider = nil
        _isActive = false
    }

    /// Convert AVAudioPCMBuffer (Float32 16kHz mono) to 16-bit PCM Data
    private static func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatData = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        var data = Data(capacity: frameCount * 2)
        let samples = floatData[0]

        for i in 0..<frameCount {
            let clamped = max(-1.0, min(1.0, samples[i]))
            var int16Value = Int16(clamped * 32767.0)
            withUnsafeBytes(of: &int16Value) { data.append(contentsOf: $0) }
        }

        return data
    }

    /// Create the appropriate provider based on settings
    public static func createProvider(
        type: TranscriptionProviderType,
        apiKey: String
    ) -> any TranscriptionProvider {
        switch type {
        case .deepgram:
            return DeepgramProvider(apiKey: apiKey)
        case .assemblyAI:
            return AssemblyAIProvider(apiKey: apiKey)
        case .openAIWhisper:
            return OpenAIWhisperProvider(apiKey: apiKey)
        }
    }
}
