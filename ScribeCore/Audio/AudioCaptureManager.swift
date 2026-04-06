@preconcurrency import AVFoundation
import Foundation

/// Orchestrates mic + system audio capture, mixing, and output streams.
public actor AudioCaptureManager {
    private let micCapture = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()
    private let mixer: AudioMixer

    private var micTask: Task<Void, Never>?
    private var systemTask: Task<Void, Never>?

    private var _isCapturing = false
    private var _audioLevel: Float = 0

    public var isCapturing: Bool { _isCapturing }
    public var audioLevel: Float { _audioLevel }

    public init() {
        self.mixer = AudioMixer()
    }

    /// Start capturing both mic and system audio.
    /// Returns two streams: recording (full mix) and transcription (VAD-filtered).
    public func startCapture() async throws -> AudioMixer.OutputStreams {
        guard !_isCapturing else {
            throw AudioCaptureError.alreadyCapturing
        }

        let outputStreams = await mixer.createOutputStreams()

        // Start mic capture and feed into mixer
        let micStream = try micCapture.start()
        micTask = Task { [mixer] in
            for await buffer in micStream {
                guard !Task.isCancelled else { break }
                await mixer.feedMic(buffer)
            }
        }

        // Start system audio capture and feed into mixer
        let systemStream = try await systemCapture.start()
        systemTask = Task { [mixer] in
            for await buffer in systemStream {
                guard !Task.isCancelled else { break }
                await mixer.feedSystem(buffer)
            }
        }

        _isCapturing = true
        return outputStreams
    }

    /// Start capturing mic only (no system audio).
    /// Useful when screen recording permission is not granted.
    public func startMicOnly() async throws -> AudioMixer.OutputStreams {
        guard !_isCapturing else {
            throw AudioCaptureError.alreadyCapturing
        }

        let outputStreams = await mixer.createOutputStreams()

        let micStream = try micCapture.start()
        micTask = Task { [mixer] in
            for await buffer in micStream {
                guard !Task.isCancelled else { break }
                await mixer.feedMic(buffer)
            }
        }

        _isCapturing = true
        return outputStreams
    }

    /// Stop all audio capture
    public func stopCapture() async {
        micTask?.cancel()
        systemTask?.cancel()
        micTask = nil
        systemTask = nil

        micCapture.stop()
        await systemCapture.stop()
        await mixer.stop()

        _isCapturing = false
        _audioLevel = 0
    }
}

// MARK: - Errors

public enum AudioCaptureError: Error, LocalizedError {
    case alreadyCapturing
    case noInputDevice
    case noDisplay
    case formatError
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .alreadyCapturing: return "Audio capture is already in progress"
        case .noInputDevice: return "No audio input device found"
        case .noDisplay: return "No display found for screen capture"
        case .formatError: return "Failed to create audio format"
        case .permissionDenied: return "Audio capture permission denied"
        }
    }
}
