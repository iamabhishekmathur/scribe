import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "CalendarManager")

/// Calendar interface powered by Google Calendar
public actor CalendarManager {
    public static let shared = CalendarManager()

    private let googleClient = GoogleCalendarClient()

    private init() {}

    public struct UpcomingMeeting: Sendable {
        public let id: String
        public let title: String
        public let startDate: Date
        public let meetingURL: String?
        public let attendees: [String]
    }

    /// Set Google access token after OAuth
    public func setGoogleToken(_ token: String) async {
        await googleClient.setAccessToken(token)
    }

    /// Get upcoming meetings from all sources, deduplicated
    public func getUpcomingMeetings(minutes: Int = 30) async -> [UpcomingMeeting] {
        var meetings: [UpcomingMeeting] = []

        await ensureGoogleToken()

        do {
            let googleEvents = try await googleClient.getUpcomingEvents(minutes: minutes)
            logger.info("Google Calendar: \(googleEvents.count) events")
            for event in googleEvents {
                meetings.append(UpcomingMeeting(
                    id: event.id,
                    title: event.title,
                    startDate: event.startDate,
                    meetingURL: event.meetingURL,
                    attendees: event.attendees
                ))
            }
        } catch {
            logger.info("Google Calendar fetch failed: \(error.localizedDescription)")
        }

        return meetings.sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Google Token Management

    /// Check if Google token needs refresh, and refresh if so
    private func ensureGoogleToken() async {
        // Check if we have a stored token
        let token = await MainActor.run { KeychainManager.shared.get(.googleOAuthToken) }
        guard token != nil else { return }

        // Check if token expiry is stored and if it's expired
        let expiryTimestamp = UserDefaults.standard.double(forKey: "googleTokenExpiresAt")
        let isExpired = expiryTimestamp > 0 && Date().timeIntervalSince1970 > expiryTimestamp

        if isExpired {
            logger.info("Google token expired, attempting refresh...")
            let refreshToken = await MainActor.run { KeychainManager.shared.get(.googleOAuthRefreshToken) }
            guard let refreshToken, !refreshToken.isEmpty else {
                logger.warning("No refresh token available")
                return
            }

            do {
                let newTokens = try await GoogleOAuthManager.shared.refreshToken(refreshToken)
                await MainActor.run {
                    try? KeychainManager.shared.set(.googleOAuthToken, value: newTokens.accessToken)
                    UserDefaults.standard.set(newTokens.expiresAt.timeIntervalSince1970, forKey: "googleTokenExpiresAt")
                }
                await googleClient.setAccessToken(newTokens.accessToken)
                logger.info("Google token refreshed successfully")
            } catch {
                logger.error("Google token refresh failed: \(error.localizedDescription)")
            }
        } else if let token {
            // Token exists and not expired — make sure client has it
            await googleClient.setAccessToken(token)
        }
    }

    /// Public method to check Google connection status
    public enum GoogleStatus: Sendable {
        case notConnected
        case connected
        case expired
    }

    public func googleConnectionStatus() async -> GoogleStatus {
        let token = await MainActor.run { KeychainManager.shared.get(.googleOAuthToken) }
        guard token != nil else { return .notConnected }

        let expiryTimestamp = UserDefaults.standard.double(forKey: "googleTokenExpiresAt")
        if expiryTimestamp > 0 && Date().timeIntervalSince1970 > expiryTimestamp {
            let refreshToken = await MainActor.run { KeychainManager.shared.get(.googleOAuthRefreshToken) }
            return refreshToken != nil ? .expired : .notConnected
        }
        return .connected
    }

}
