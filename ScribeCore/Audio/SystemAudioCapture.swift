import ScreenCaptureKit
@preconcurrency import AVFoundation
import Foundation
import CoreMedia

/// Captures system audio via ScreenCaptureKit (macOS 13+).
/// Excludes own app audio to prevent feedback loops.
public final class SystemAudioCapture: @unchecked Sendable {
    private var stream: SCStream?
    private var _isCapturing = false
    private let delegate = StreamDelegate()

    public var isCapturing: Bool { _isCapturing }

    public init() {}

    /// Start capturing system audio (excluding this app).
    /// Returns an AsyncStream of PCM buffers.
    public func start() async throws -> AsyncStream<AVAudioPCMBuffer> {
        guard !_isCapturing else {
            throw AudioCaptureError.alreadyCapturing
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplay
        }

        // Exclude our own app from capture to avoid feedback
        let excludedApps = content.applications.filter { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = Int(MicrophoneCapture.targetSampleRate)
        config.channelCount = Int(MicrophoneCapture.targetChannelCount)

        // Minimize video overhead since we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)

        let audioStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.delegate.continuation = continuation
        }

        try scStream.addStreamOutput(delegate, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try await scStream.startCapture()

        self.stream = scStream
        _isCapturing = true

        return audioStream
    }

    public func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        delegate.continuation?.finish()
        delegate.continuation = nil
        _isCapturing = false
    }
}

// MARK: - Stream Delegate

private final class StreamDelegate: NSObject, SCStreamOutput, @unchecked Sendable {
    var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }

        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        var asbdValue = asbd.pointee
        guard let audioFormat = AVAudioFormat(streamDescription: &asbdValue) else {
            return
        }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return
        }
        pcmBuffer.frameLength = frameCount

        // Copy sample buffer audio data into PCM buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<CChar>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let dataPointer else { return }

        let mutableABL = pcmBuffer.mutableAudioBufferList
        let byteCount = min(totalLength, Int(mutableABL.pointee.mBuffers.mDataByteSize))
        if let dest = mutableABL.pointee.mBuffers.mData {
            memcpy(dest, dataPointer, byteCount)
            mutableABL.pointee.mBuffers.mDataByteSize = UInt32(byteCount)
        }

        // Send buffer — nonisolated(unsafe) because we know the continuation
        // is only written to from init and the buffer is fully prepared here.
        nonisolated(unsafe) let buf = pcmBuffer
        continuation?.yield(buf)
    }
}
