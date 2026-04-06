@preconcurrency import AVFoundation
import Foundation

/// Mixes mic and system audio into two output paths:
/// 1. Recording path (full mix) — for archival
/// 2. Transcription path (VAD-filtered) — for sending to transcription provider
public actor AudioMixer {
    private let vadFilter: VADFilter
    private var recordingContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var transcriptionContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    public init(vadFilter: VADFilter = VADFilter()) {
        self.vadFilter = vadFilter
    }

    public struct OutputStreams: Sendable {
        /// Full mix of all audio — for recording
        public let recording: AsyncStream<AVAudioPCMBuffer>
        /// VAD-filtered audio — for transcription
        public let transcription: AsyncStream<AVAudioPCMBuffer>
    }

    /// Create the two output streams. Call `feed(mic:)` and `feed(system:)` to push audio.
    public func createOutputStreams() -> OutputStreams {
        let recording = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.recordingContinuation = continuation
        }
        let transcription = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.transcriptionContinuation = continuation
        }
        return OutputStreams(recording: recording, transcription: transcription)
    }

    /// Feed a microphone buffer into the mixer
    public func feedMic(_ buffer: AVAudioPCMBuffer) async {
        // Always send to recording path
        recordingContinuation?.yield(buffer)

        // Only send to transcription if VAD passes
        if await vadFilter.shouldPass(buffer: buffer) {
            transcriptionContinuation?.yield(buffer)
        }
    }

    /// Feed a system audio buffer into the mixer
    /// System audio (other participants) bypasses VAD — we want to transcribe everything they say
    public func feedSystem(_ buffer: AVAudioPCMBuffer) async {
        recordingContinuation?.yield(buffer)
        transcriptionContinuation?.yield(buffer)
    }

    /// Close both output streams
    public func stop() {
        recordingContinuation?.finish()
        transcriptionContinuation?.finish()
        recordingContinuation = nil
        transcriptionContinuation = nil
    }
}
