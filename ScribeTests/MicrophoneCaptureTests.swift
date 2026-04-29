import Testing
@testable import ScribeCore
@preconcurrency import AVFoundation
import Foundation

@Suite("MicrophoneCapture")
struct MicrophoneCaptureTests {

    @Test("rmsLevel returns zero for empty buffer")
    func rmsZeroForEmpty() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 0
        #expect(MicrophoneCapture.rmsLevel(from: buffer) == 0)
    }

    @Test("rmsLevel scales with signal magnitude")
    func rmsScalesWithMagnitude() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let frames: AVAudioFrameCount = 1024

        let quiet = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        quiet.frameLength = frames
        let qSamples = quiet.floatChannelData![0]
        for i in 0..<Int(frames) { qSamples[i] = 0.01 }

        let loud = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        loud.frameLength = frames
        let lSamples = loud.floatChannelData![0]
        for i in 0..<Int(frames) { lSamples[i] = 0.2 }

        let rmsQuiet = MicrophoneCapture.rmsLevel(from: quiet)
        let rmsLoud = MicrophoneCapture.rmsLevel(from: loud)
        #expect(rmsLoud > rmsQuiet)
        #expect(rmsLoud <= 1.0)
    }

    @Test("Target format constants match Deepgram requirements")
    func targetFormatConstants() {
        // Deepgram is configured with sample_rate=16000, channels=1, encoding=linear16.
        // The mic must produce 16kHz mono so the converter doesn't have to resample again
        // before serialization in TranscriptionManager.bufferToData.
        #expect(MicrophoneCapture.targetSampleRate == 16000)
        #expect(MicrophoneCapture.targetChannelCount == 1)
    }

    @Test("Calling stop() before start() does not crash")
    func stopBeforeStart() {
        let mic = MicrophoneCapture()
        mic.stop()
        #expect(mic.isCapturing == false)
    }
}
