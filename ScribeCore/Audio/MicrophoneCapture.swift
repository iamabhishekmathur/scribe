@preconcurrency import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "MicrophoneCapture")

/// Captures microphone audio, converts to 16kHz mono PCM Float32,
/// and emits buffers via an AsyncStream.
///
/// Bluetooth/AirPods handling: when an SCO/HFP route negotiation is in progress, the input node
/// can briefly report `sampleRate == 0`. We retry a few times with a short delay before failing.
/// We also subscribe to `AVAudioEngineConfigurationChange`, which fires when the default input
/// device or its format changes — on those events we rebuild the converter and tap with the new
/// input format and restart the engine.
public final class MicrophoneCapture: @unchecked Sendable {
    private let stateLock = NSLock()
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var configChangeObserver: NSObjectProtocol?
    private var _isCapturing = false

    public var isCapturing: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _isCapturing
    }

    // Target format: 16kHz mono PCM Float32
    public static let targetSampleRate: Double = 16000
    public static let targetChannelCount: AVAudioChannelCount = 1

    // Tunables for transient 0-rate tolerance during route negotiation.
    static let inputFormatRetryAttempts: Int = 5
    static let inputFormatRetryDelay: TimeInterval = 0.1

    public init() {}

    /// Returns an AsyncStream of PCM buffers at 16kHz mono.
    /// Call `stop()` to end the stream.
    public func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        stateLock.lock()
        if _isCapturing {
            stateLock.unlock()
            throw AudioCaptureError.alreadyCapturing
        }
        stateLock.unlock()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let inputFormat = try Self.resolveInputFormat(node: inputNode)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannelCount,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.formatError
        }

        let stream = AsyncStream<AVAudioPCMBuffer> { [weak self] continuation in
            guard let self else { return }
            self.stateLock.lock()
            self.continuation = continuation
            self.engine = engine
            self.converter = converter
            self.stateLock.unlock()

            self.installTap(on: inputNode, inputFormat: inputFormat, targetFormat: targetFormat)
        }

        // Subscribe to configuration changes BEFORE start so route flips during start are caught.
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange(targetFormat: targetFormat)
        }

        try engine.start()
        logger.info("MicrophoneCapture started — input rate=\(inputFormat.sampleRate, privacy: .public) ch=\(inputFormat.channelCount, privacy: .public)")

        stateLock.lock()
        _isCapturing = true
        stateLock.unlock()

        return stream
    }

    public func stop() {
        stateLock.lock()
        let eng = engine
        let cont = continuation
        let obs = configChangeObserver
        engine = nil
        converter = nil
        continuation = nil
        configChangeObserver = nil
        _isCapturing = false
        stateLock.unlock()

        if let obs {
            NotificationCenter.default.removeObserver(obs)
        }
        eng?.inputNode.removeTap(onBus: 0)
        eng?.stop()
        cont?.finish()
        logger.info("MicrophoneCapture stopped")
    }

    // MARK: - Helpers

    /// Read the input node's format, retrying briefly when the system reports `0` (which happens
    /// while a Bluetooth route is negotiating).
    private static func resolveInputFormat(node: AVAudioInputNode) throws -> AVAudioFormat {
        for attempt in 0..<inputFormatRetryAttempts {
            let fmt = node.outputFormat(forBus: 0)
            if fmt.sampleRate > 0 && fmt.channelCount > 0 {
                if attempt > 0 {
                    logger.info("Resolved input format after \(attempt, privacy: .public) retries: rate=\(fmt.sampleRate, privacy: .public)")
                }
                return fmt
            }
            logger.warning("Input format reports zero rate (attempt \(attempt + 1, privacy: .public)/\(inputFormatRetryAttempts, privacy: .public)) — likely Bluetooth route negotiating")
            Thread.sleep(forTimeInterval: inputFormatRetryDelay)
        }
        throw AudioCaptureError.noInputDevice
    }

    private func installTap(on node: AVAudioInputNode, inputFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        node.removeTap(onBus: 0)
        // Capture converter via the lock to ensure we use the current instance after a route change.
        node.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.stateLock.lock()
            let conv = self.converter
            let cont = self.continuation
            self.stateLock.unlock()
            guard let conv, let cont else { return }

            let outputFrameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * Self.targetSampleRate / inputFormat.sampleRate
            )
            guard outputFrameCapacity > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCapacity
            ) else { return }

            var error: NSError?
            let status = conv.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .haveData, convertedBuffer.frameLength > 0 {
                cont.yield(convertedBuffer)
            }
        }
    }

    /// Triggered when the engine reports a configuration change — typically a default input
    /// device swap (built-in <-> AirPods) or sample-rate change. The engine is in a stopped
    /// state when this fires; we rebuild the converter and tap and restart.
    private func handleConfigurationChange(targetFormat: AVAudioFormat) {
        stateLock.lock()
        let eng = engine
        let wasCapturing = _isCapturing
        stateLock.unlock()

        guard let eng, wasCapturing else { return }

        logger.info("Audio engine configuration changed — rebuilding tap")

        do {
            let inputNode = eng.inputNode
            let newInputFormat = try Self.resolveInputFormat(node: inputNode)

            guard let newConverter = AVAudioConverter(from: newInputFormat, to: targetFormat) else {
                logger.error("Failed to create converter for new input format")
                return
            }

            stateLock.lock()
            converter = newConverter
            stateLock.unlock()

            installTap(on: inputNode, inputFormat: newInputFormat, targetFormat: targetFormat)

            if !eng.isRunning {
                try eng.start()
            }
            logger.info("MicrophoneCapture rebuilt — new input rate=\(newInputFormat.sampleRate, privacy: .public) ch=\(newInputFormat.channelCount, privacy: .public)")
        } catch {
            logger.error("Failed to rebuild tap after configuration change: \(error.localizedDescription)")
        }
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
