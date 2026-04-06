import Foundation

/// Meeting lifecycle state machine
public enum MeetingState: String, Sendable {
    case idle
    case detected
    case recording
    case ended
    case processing
    case complete
}

/// Represents an active or completed meeting session
public actor MeetingSession {
    public let id: UUID
    public let title: String
    public private(set) var state: MeetingState = .idle
    public let startTime: Date
    public private(set) var endTime: Date?
    public private(set) var calendarEventId: String?
    public private(set) var meetingURL: String?

    public init(
        id: UUID = UUID(),
        title: String,
        startTime: Date = Date(),
        calendarEventId: String? = nil,
        meetingURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.calendarEventId = calendarEventId
        self.meetingURL = meetingURL
    }

    /// Transition to detected state (meeting signals found)
    public func markDetected() throws {
        guard state == .idle else {
            throw MeetingSessionError.invalidTransition(from: state, to: .detected)
        }
        state = .detected
    }

    /// Transition to recording state
    public func startRecording() throws {
        guard state == .idle || state == .detected else {
            throw MeetingSessionError.invalidTransition(from: state, to: .recording)
        }
        state = .recording
    }

    /// Transition to ended state
    public func endRecording() throws {
        guard state == .recording else {
            throw MeetingSessionError.invalidTransition(from: state, to: .ended)
        }
        state = .ended
        endTime = Date()
    }

    /// Transition to processing state (AI summarization)
    public func startProcessing() throws {
        guard state == .ended else {
            throw MeetingSessionError.invalidTransition(from: state, to: .processing)
        }
        state = .processing
    }

    /// Transition to complete state
    public func markComplete() throws {
        guard state == .processing else {
            throw MeetingSessionError.invalidTransition(from: state, to: .complete)
        }
        state = .complete
    }

    /// Duration in seconds (nil if not ended)
    public var duration: TimeInterval? {
        guard let endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    /// Create a MeetingRecord for DB persistence
    public func toRecord() -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: title,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            calendarEventId: calendarEventId,
            meetingURL: meetingURL,
            state: state.rawValue
        )
    }
}

public enum MeetingSessionError: Error, LocalizedError {
    case invalidTransition(from: MeetingState, to: MeetingState)

    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let from, let to):
            return "Invalid meeting state transition: \(from.rawValue) -> \(to.rawValue)"
        }
    }
}
