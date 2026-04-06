import AppKit
import ScribeCore
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var detectionTask: Task<Void, Never>?
    private var calendarRefreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)

        // Set app icon from bundled resources
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Assets.xcassets/AppIcon.appiconset"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        } else if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
                  let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }

        Task {
            // Initialize database
            do {
                try await Database.shared.initialize()

                // Clean up orphaned "recording" meetings from previous crashes/restarts
                let allMeetings = (try? await MeetingStore.shared.getAllMeetings(limit: 50)) ?? []
                for meeting in allMeetings where meeting.state == "recording" {
                    logger.info("Cleaning up orphaned recording: \(meeting.title)")
                    try? await MeetingStore.shared.endMeeting(id: meeting.id)
                    try? await MeetingStore.shared.completeMeeting(id: meeting.id)
                }
            } catch {
                logger.error("Failed to initialize database: \(error.localizedDescription)")
            }

            // Start local API server
            do {
                try await LocalAPIServer.shared.start()
            } catch {
                logger.error("Failed to start API server: \(error.localizedDescription)")
            }

            // Register notification categories
            if Bundle.main.bundleIdentifier != nil {
                await MeetingDetector.registerNotificationCategories()
            }

            // Sync Google Calendar at startup — always refresh token first
            let hasGoogleToken = await MainActor.run { KeychainManager.shared.hasKey(.googleOAuthToken) }
            if hasGoogleToken {
                // Force a token refresh at startup to ensure we have a valid token
                if let refreshToken = await MainActor.run(body: { KeychainManager.shared.get(.googleOAuthRefreshToken) }) {
                    do {
                        let newTokens = try await GoogleOAuthManager.shared.refreshToken(refreshToken)
                        await MainActor.run {
                            try? KeychainManager.shared.set(.googleOAuthToken, value: newTokens.accessToken)
                            UserDefaults.standard.set(newTokens.expiresAt.timeIntervalSince1970, forKey: "googleTokenExpiresAt")
                        }
                        await CalendarManager.shared.setGoogleToken(newTokens.accessToken)
                        logger.info("Google token refreshed at startup")
                    } catch {
                        logger.warning("Startup token refresh failed: \(error.localizedDescription)")
                        // Fall back to stored token
                        if let token = await MainActor.run(body: { KeychainManager.shared.get(.googleOAuthToken) }) {
                            await CalendarManager.shared.setGoogleToken(token)
                        }
                    }
                }
                var events = await CalendarManager.shared.getUpcomingMeetings(minutes: 1440)
                if events.count < 5 {
                    events = await CalendarManager.shared.getUpcomingMeetings(minutes: 4320) // 72h
                }
                logger.info("Startup calendar sync: \(events.count) upcoming events")
            }

            // Start background calendar refresh (every 5 minutes)
            startCalendarRefreshLoop()

            // Start meeting detection if enabled
            let settings = await MainActor.run { AppSettings.shared }
            if await MainActor.run(body: { settings.autoDetectMeetings }) {
                await startMeetingDetection()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        detectionTask?.cancel()
        calendarRefreshTask?.cancel()
        Task {
            await LocalAPIServer.shared.stop()
            await MeetingDetector.shared.stopMonitoring()
        }
    }

    // MARK: - Calendar Refresh

    private func startCalendarRefreshLoop() {
        calendarRefreshTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300)) // Every 5 minutes
                if let token = await MainActor.run(body: { KeychainManager.shared.get(.googleOAuthToken) }) {
                    await CalendarManager.shared.setGoogleToken(token)
                    let events = await CalendarManager.shared.getUpcomingMeetings(minutes: 1440)
                    await MainActor.run {
                        logger.info("Calendar refresh: \(events.count) events")
                    }
                }
            }
        }
    }

    // MARK: - Meeting Detection

    private func startMeetingDetection() async {
        logger.info("Starting meeting detection...")
        let detector = MeetingDetector.shared
        let events = await detector.startMonitoring()

        detectionTask = Task {
            for await event in events {
                guard !Task.isCancelled else { break }
                switch event {
                case .calendarEvent(let title, _, _, _):
                    logger.info("Meeting detected (calendar): \(title)")
                    await showMeetingAlert(title: "Meeting Starting", body: title)
                case .appLaunched(let appName, _):
                    logger.info("Meeting started in \(appName)")
                    await showMeetingAlert(title: "Meeting in \(appName)", body: "Start scribing?")
                case .appClosed(let appName, _):
                    logger.info("Meeting ended in \(appName)")
                    if RecordingCoordinator.shared.isRecording {
                        logger.info("Auto-stopping scribing because meeting ended in \(appName)")
                        await RecordingCoordinator.shared.stopRecording()
                    }
                case .audioActivity:
                    logger.info("Meeting-like audio activity detected")
                    await showMeetingAlert(title: "Meeting Detected", body: "Start scribing?")
                case .browserMeeting:
                    logger.info("Browser meeting detected (Google Meet)")
                    await showMeetingAlert(title: "Google Meet Detected", body: "Start scribing?")
                }
            }
        }
        logger.info("Meeting detection started")
    }

    /// Show a floating notification banner in the top-right (like Zoom/Granola)
    @MainActor
    private func showMeetingAlert(title: String, body: String) {
        // Don't show if already scribing
        guard !RecordingCoordinator.shared.isRecording else {
            logger.info("Skipping meeting alert — already scribing")
            return
        }

        ScribeNotificationBanner.show(title: title, subtitle: body, actionTitle: "Start Scribing") {
            let meetingId = UUID()
            Task {
                await RecordingCoordinator.shared.startRecording(meetingId: meetingId, title: title)
                // Open the meeting page
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .openMeeting, object: meetingId)
                }
            }
        }
    }
}
