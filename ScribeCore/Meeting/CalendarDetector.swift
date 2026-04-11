import EventKit
import Foundation

/// Detects upcoming meetings from the local calendar (EventKit) and Google Calendar.
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
    public func start(pollInterval: TimeInterval = 20) -> AsyncStream<DetectedMeeting> {
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

    private func checkUpcomingMeetings() async -> [DetectedMeeting] {
        var detected: [DetectedMeeting] = []

        // 1. EventKit (local macOS Calendar) — only works with bundled .app
        if Bundle.main.bundleIdentifier != nil {
            detected.append(contentsOf: checkEventKit())
        }

        // 2. Google Calendar — works regardless of bundle identifier
        let googleMeetings = await checkGoogleCalendar()
        for gm in googleMeetings {
            let key = "\(gm.title)-\(Int(gm.startDate.timeIntervalSince1970))"
            guard !detectedEventIds.contains(key) else { continue }
            detectedEventIds.insert(key)
            detected.append(gm)
        }

        return detected
    }

    // MARK: - EventKit

    private func checkEventKit() -> [DetectedMeeting] {
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

            guard !detectedEventIds.contains(eventId) else { continue }

            let meetingURL = extractMeetingURL(from: event)
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

    // MARK: - Google Calendar

    private func checkGoogleCalendar() async -> [DetectedMeeting] {
        let meetings = await CalendarManager.shared.getUpcomingMeetings(minutes: Int(lookAheadMinutes))
        var detected: [DetectedMeeting] = []

        for meeting in meetings {
            let key = "google-\(meeting.id)"
            guard !detectedEventIds.contains(key) else { continue }

            let attendeeCount = meeting.attendees.count
            guard meeting.meetingURL != nil || attendeeCount > 1 else { continue }

            detectedEventIds.insert(key)

            detected.append(DetectedMeeting(
                title: meeting.title,
                startDate: meeting.startDate,
                eventId: meeting.id,
                meetingURL: meeting.meetingURL,
                participants: meeting.attendees
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
