import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "GoogleCalendar")

/// Google Calendar REST API client
public actor GoogleCalendarClient {
    private let baseURL = "https://www.googleapis.com/calendar/v3"
    private var accessToken: String?

    public init() {}

    public func setAccessToken(_ token: String) {
        self.accessToken = token
    }

    /// Fetch upcoming events from primary calendar
    public func getUpcomingEvents(minutes: Int = 30) async throws -> [GoogleCalendarEvent] {
        guard let token = accessToken else {
            throw GoogleCalendarError.notAuthenticated
        }

        let now = ISO8601DateFormatter().string(from: Date())
        let later = ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(minutes * 60)))

        var components = URLComponents(string: "\(baseURL)/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: now),
            URLQueryItem(name: "timeMax", value: later),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "10"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.requestFailed
        }

        if http.statusCode == 401 {
            // Token expired — try refresh and retry once
            logger.info("Google token expired (401), attempting refresh...")
            if await refreshAndRetry() {
                return try await fetchEvents(token: accessToken!, components: components)
            }
            throw GoogleCalendarError.requestFailed
        }

        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            logger.error("Google Calendar API error: HTTP \(http.statusCode) - \(body)")
            throw GoogleCalendarError.requestFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { parseEvent($0) }
    }

    private func parseEvent(_ json: [String: Any]) -> GoogleCalendarEvent? {
        guard let id = json["id"] as? String,
              let summary = json["summary"] as? String else { return nil }

        let startObj = json["start"] as? [String: Any]
        let startStr = (startObj?["dateTime"] as? String) ?? (startObj?["date"] as? String) ?? ""
        let startDate = ISO8601DateFormatter().date(from: startStr) ?? Date()

        // Extract conference data (Zoom, Meet, etc.)
        var meetingURL: String?
        if let conference = json["conferenceData"] as? [String: Any],
           let entryPoints = conference["entryPoints"] as? [[String: Any]] {
            meetingURL = entryPoints.first(where: { ($0["entryPointType"] as? String) == "video" })?["uri"] as? String
        }

        // Fallback: check location and description for meeting URLs
        if meetingURL == nil {
            let location = json["location"] as? String ?? ""
            let description = json["description"] as? String ?? ""
            meetingURL = extractMeetingURL(from: location) ?? extractMeetingURL(from: description)
        }

        let attendees = (json["attendees"] as? [[String: Any]])?.compactMap { $0["email"] as? String } ?? []

        return GoogleCalendarEvent(
            id: id,
            title: summary,
            startDate: startDate,
            meetingURL: meetingURL,
            attendees: attendees
        )
    }

    private func extractMeetingURL(from text: String) -> String? {
        let patterns = [
            "https://meet\\.google\\.com/[a-z-]+",
            "https://[\\w.]*zoom\\.us/j/\\d+",
            "https://teams\\.microsoft\\.com/[^\\s]+",
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return String(text[range])
            }
        }
        return nil
    }

    /// Refresh token and update stored credentials
    private func refreshAndRetry() async -> Bool {
        let refreshToken = await MainActor.run { KeychainManager.shared.get(.googleOAuthRefreshToken) }
        guard let refreshToken, !refreshToken.isEmpty else {
            logger.warning("No refresh token for auto-refresh")
            return false
        }
        do {
            let newTokens = try await GoogleOAuthManager.shared.refreshToken(refreshToken)
            self.accessToken = newTokens.accessToken
            await MainActor.run {
                try? KeychainManager.shared.set(.googleOAuthToken, value: newTokens.accessToken)
                UserDefaults.standard.set(newTokens.expiresAt.timeIntervalSince1970, forKey: "googleTokenExpiresAt")
            }
            logger.info("Token refreshed successfully inside GoogleCalendarClient")
            return true
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Fetch events with a specific token (used for retry after refresh)
    private func fetchEvents(token: String, components: URLComponents) async throws -> [GoogleCalendarEvent] {
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GoogleCalendarError.requestFailed
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { parseEvent($0) }
    }
}

public struct GoogleCalendarEvent: Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let meetingURL: String?
    public let attendees: [String]
}

public enum GoogleCalendarError: Error, LocalizedError {
    case notAuthenticated
    case requestFailed

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated with Google"
        case .requestFailed: return "Google Calendar request failed"
        }
    }
}
