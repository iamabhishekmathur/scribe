import EventKit
import Foundation

/// Detects upcoming meetings from the local calendar (EventKit).
/// Looks for events with video call URLs starting within a configurable window.
public actor CalendarDetector {
    private let eventStore = EKEventStore()
    private var pollTask: Task<Void, Never>?
    private var detectedEventIds: Set<String> = []

    /// How many minutes before an event to trigger detection
    public let lookAheadMinutes: Double

    public init(lookAheadMinutes: Double = 2.0) {
        self.lookAheadMinutes = lookAheadMinutes
    }

    public struct DetectedMeeting: Sendable {
        public let title: String
        public let startDate: Date
        public let eventId: String
        public let meetingURL: String?
        public let participants: [String]
    }

    /// Start polling for upcoming meetings. Yields detected meetings via the returned stream.
    public func start(pollInterval: TimeInterval = 30) -> AsyncStream<DetectedMeeting> {
        AsyncStream { continuation in
            self.pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    if let self {
                        let meetings = await self.checkUpcomingMeetings()
                        for meeting in meetings {
                            continuation.yield(meeting)
                        }
                    }
                    try? await Task.sleep(for: .seconds(pollInterval))
                }
                continuation.finish()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func checkUpcomingMeetings() -> [DetectedMeeting] {
        // Skip EventKit for unsigned apps — causes CADatabase error spam
        guard Bundle.main.bundleIdentifier != nil else { return [] }

        let now = Date()
        let lookAhead = now.addingTimeInterval(lookAheadMinutes * 60)

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: lookAhead,
            calendars: nil
        )
        let events = eventStore.events(matching: predicate)

        var detected: [DetectedMeeting] = []

        for event in events {
            let eventId = event.eventIdentifier ?? UUID().uuidString

            // Skip already-detected events
            guard !detectedEventIds.contains(eventId) else { continue }

            // Check if this event has a video call URL
            let meetingURL = extractMeetingURL(from: event)

            // Only detect events that look like meetings (have URL or multiple attendees)
            let attendeeCount = event.attendees?.count ?? 0
            guard meetingURL != nil || attendeeCount > 1 else { continue }

            detectedEventIds.insert(eventId)

            let participants = event.attendees?.compactMap { $0.name } ?? []

            detected.append(DetectedMeeting(
                title: event.title ?? "Untitled Meeting",
                startDate: event.startDate,
                eventId: eventId,
                meetingURL: meetingURL,
                participants: participants
            ))
        }

        return detected
    }

    /// Extract video meeting URL from event notes, URL field, or location
    private func extractMeetingURL(from event: EKEvent) -> String? {
        let patterns = [
            "https://meet.google.com/[a-z-]+",
            "https://.*\\.zoom\\.us/j/\\d+",
            "https://teams\\.microsoft\\.com/l/meetup-join/[^\\s]+",
            "https://.*\\.webex\\.com/[^\\s]+",
        ]

        let sources = [event.url?.absoluteString, event.location, event.notes]

        for source in sources {
            guard let text = source else { continue }
            for pattern in patterns {
                if let range = text.range(of: pattern, options: .regularExpression) {
                    return String(text[range])
                }
            }
        }

        return nil
    }
}
