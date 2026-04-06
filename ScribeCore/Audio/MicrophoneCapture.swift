@preconcurrency import AVFoundation
import Foundation

/// Captures microphone audio, converts to 16kHz mono PCM Float32,
/// and emits buffers via an AsyncStream.
public final class MicrophoneCapture: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var _isCapturing = false

    public var isCapturing: Bool { _isCapturing }

    // Target format: 16kHz mono PCM Float32
    public static let targetSampleRate: Double = 16000
    public static let targetChannelCount: AVAudioChannelCount = 1

    public init() {}

    /// Returns an AsyncStream of PCM buffers at 16kHz mono.
    /// Call `stop()` to end the stream.
    public func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        guard !_isCapturing else {
            throw AudioCaptureError.alreadyCapturing
        }

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannelCount,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        guard let converter else {
            throw AudioCaptureError.formatError
        }

        let stream = AsyncStream<AVAudioPCMBuffer> { [weak self] continuation in
            self?.continuation = continuation

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
                let outputFrameCapacity = AVAudioFrameCount(
                    Double(buffer.frameLength) * Self.targetSampleRate / inputFormat.sampleRate
                )
                guard outputFrameCapacity > 0 else { return }

                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: outputFrameCapacity
                ) else { return }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .haveData, convertedBuffer.frameLength > 0 {
                    continuation.yield(convertedBuffer)
                }
            }
        }

        try engine.start()
        _isCapturing = true

        return stream
    }

    public func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        continuation?.finish()
        continuation = nil
        _isCapturing = false
    }

    /// Returns the current RMS level (0.0 - 1.0) from a buffer
    public static func rmsLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData,
              buffer.frameLength > 0 else { return 0 }

        let frames = Int(buffer.frameLength)
        let samples = channelData[0]
        var sum: Float = 0

        for i in 0..<frames {
            let sample = samples[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frames))
        // Clamp to 0-1 range (typical speech RMS is 0.01-0.3)
        return min(rms * 5.0, 1.0)
    }
}
