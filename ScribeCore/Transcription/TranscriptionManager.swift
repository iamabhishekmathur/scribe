@preconcurrency import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "TranscriptionManager")

/// Manages the pending segment merge state in an actor-safe way
private actor SegmentMerger {
    private var pending: TranscriptSegment?
    private var written = false
    private var dirty = false
    private let mergeGap: TimeInterval

    init(mergeGap: TimeInterval) {
        self.mergeGap = mergeGap
    }

    /// Process a new result. Returns a completed segment to flush if speaker changed, nil otherwise.
    func process(result: TranscriptionResult, meetingId: UUID) -> TranscriptSegment? {
        var flushed: TranscriptSegment?

        if var p = pending {
            let sameSpeaker = p.speakerIndex == result.speakerIndex && p.speaker == result.speaker
            let smallGap = result.startTime - p.endTime < mergeGap

            if sameSpeaker && smallGap {
                // Merge into pending
                p.text += " " + result.text
                p.endTime = result.endTime
                p.confidence = min(p.confidence ?? 1.0, result.confidence ?? 1.0)
                pending = p
                dirty = true
                return nil
            } else {
                // Speaker changed — return old for flushing
                flushed = p
                flushed?.isFinal = true
            }
        }

        // Start new pending
        pending = TranscriptSegment(
            meetingId: meetingId,
            speaker: result.speaker,
            speakerIndex: result.speakerIndex,
            text: result.text,
            startTime: result.startTime,
            endTime: result.endTime,
            confidence: result.confidence,
            isFinal: true
        )
        written = false
        dirty = false

        return flushed
    }

    struct FlushAction {
        enum Kind { case insert, update, none }
        let kind: Kind
        let segment: TranscriptSegment?
    }

    /// Get current pending segment for periodic DB flush
    func flushAction() -> FlushAction {
        guard let seg = pending else { return FlushAction(kind: .none, segment: nil) }
        if !written {
            written = true
            dirty = false
            return FlushAction(kind: .insert, segment: seg)
        } else if dirty {
            dirty = false
            return FlushAction(kind: .update, segment: seg)
        }
        return FlushAction(kind: .none, segment: nil)
    }

    /// Get the final pending segment for end-of-stream flush
    func finalFlush() -> FlushAction {
        flushAction()
    }

    func clear() {
        pending = nil
        written = false
        dirty = false
    }
}

/// Bridges audio capture to the active transcription provider.
/// Converts PCM buffers to raw data, sends to provider, writes results to DB.
/// Merges consecutive segments from the same speaker into single DB rows.
public final class TranscriptionManager: @unchecked Sendable {
    private var provider: (any TranscriptionProvider)?
    private var processingTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var merger: SegmentMerger?
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
        let merger = SegmentMerger(mergeGap: 3.0)
        self.merger = merger

        // Process incoming audio
        processingTask = Task.detached {
            for await buffer in audioStream {
                guard !Task.isCancelled else { break }
                if let data = Self.bufferToData(buffer) {
                    try? await provider.sendAudio(data)
                }
            }
        }

        // Periodic flush — writes/updates pending segment to DB so UI sees it live
        flushTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { break }
                let action = await merger.flushAction()
                if let seg = action.segment {
                    switch action.kind {
                    case .insert: try? await store.addTranscriptSegment(seg)
                    case .update: try? await store.updateTranscriptSegment(seg)
                    case .none: break
                    }
                }
            }
        }

        // Process transcription results — merge same-speaker segments
        resultsTask = Task.detached {
            for await result in provider.results {
                guard !Task.isCancelled else { break }
                guard result.isFinal else { continue }

                let flushed = await merger.process(result: result, meetingId: meetingId)
                if let flushed {
                    // Completed segment (speaker changed) — write to DB
                    try? await store.addTranscriptSegment(flushed)
                }
            }

            // Stream ended — flush remaining
            let action = await merger.finalFlush()
            if let seg = action.segment {
                switch action.kind {
                case .insert: try? await store.addTranscriptSegment(seg)
                case .update: try? await store.updateTranscriptSegment(seg)
                case .none: break
                }
            }
        }
    }

    /// Stop transcription
    public func stop() async {
        processingTask?.cancel()
        resultsTask?.cancel()
        flushTask?.cancel()
        processingTask = nil
        resultsTask = nil
        flushTask = nil

        // Final flush
        if let merger {
            let store = MeetingStore.shared
            let action = await merger.finalFlush()
            if let seg = action.segment {
                switch action.kind {
                case .insert: try? await store.addTranscriptSegment(seg)
                case .update: try? await store.updateTranscriptSegment(seg)
                case .none: break
                }
            }
            await merger.clear()
        }

        await provider?.disconnect()
        provider = nil
        merger = nil
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
