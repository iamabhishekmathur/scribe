import Foundation

/// Detects meeting-like audio activity by monitoring simultaneous mic + system audio speech.
/// Triggers when both mic and system audio are active for a sustained period.
public actor AudioActivityDetector {
    private var micActive = false
    private var systemActive = false
    private var bothActiveStart: Date?
    private var _isMeetingLikeActivity = false

    /// Duration (seconds) of simultaneous speech needed to trigger detection
    public let triggerThreshold: TimeInterval

    /// RMS level threshold for considering a source "active"
    public let rmsThreshold: Float

    public var isMeetingLikeActivity: Bool { _isMeetingLikeActivity }

    public init(triggerThreshold: TimeInterval = 10.0, rmsThreshold: Float = 0.01) {
        self.triggerThreshold = triggerThreshold
        self.rmsThreshold = rmsThreshold
    }

    /// Update with current mic audio level
    public func updateMicLevel(_ rms: Float) {
        micActive = rms >= rmsThreshold
        checkActivity()
    }

    /// Update with current system audio level
    public func updateSystemLevel(_ rms: Float) {
        systemActive = rms >= rmsThreshold
        checkActivity()
    }

    /// Reset detection state
    public func reset() {
        micActive = false
        systemActive = false
        bothActiveStart = nil
        _isMeetingLikeActivity = false
    }

    private func checkActivity() {
        let now = Date()

        if micActive && systemActive {
            // Both sources active
            if bothActiveStart == nil {
                bothActiveStart = now
            } else if let start = bothActiveStart,
                      now.timeIntervalSince(start) >= triggerThreshold {
                _isMeetingLikeActivity = true
            }
        } else {
            // One or both sources silent — reset the timer
            bothActiveStart = nil
            // Don't reset _isMeetingLikeActivity immediately to avoid flapping
        }
    }
}
