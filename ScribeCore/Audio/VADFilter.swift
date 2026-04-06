@preconcurrency import AVFoundation
import Foundation

/// Energy-based Voice Activity Detection filter.
/// Uses RMS threshold with hysteresis to detect speech.
public actor VADFilter {
    /// RMS threshold for voice detection (typical speech: 0.01-0.3)
    private let rmsThreshold: Float
    /// How long to keep "active" after last speech detected (seconds)
    private let hysteresisSeconds: Double
    /// Current speech state
    private var isSpeechActive = false
    /// Timestamp of last detected speech
    private var lastSpeechTime: Date?

    public init(rmsThreshold: Float = 0.01, hysteresisSeconds: Double = 0.3) {
        self.rmsThreshold = rmsThreshold
        self.hysteresisSeconds = hysteresisSeconds
    }

    /// Returns true if the buffer contains speech (or we're in the hysteresis window).
    public func shouldPass(buffer: AVAudioPCMBuffer) -> Bool {
        let rms = MicrophoneCapture.rmsLevel(from: buffer)
        let now = Date()

        if rms >= rmsThreshold {
            isSpeechActive = true
            lastSpeechTime = now
            return true
        }

        // Check hysteresis — keep passing for a short time after speech stops
        if isSpeechActive, let lastSpeech = lastSpeechTime {
            if now.timeIntervalSince(lastSpeech) < hysteresisSeconds {
                return true
            }
            isSpeechActive = false
        }

        return false
    }

    /// Reset the filter state
    public func reset() {
        isSpeechActive = false
        lastSpeechTime = nil
    }
}
