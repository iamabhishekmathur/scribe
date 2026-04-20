import AppKit
import UserNotifications
import ScribeCore
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var detectionTask: Task<Void, Never>?
    private var calendarRefreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)

        // Set app icon — the .icns is in Contents/Resources/ (placed by build-dmg.sh)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
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

            // Import any markdown meeting files not yet in SQLite
            await MarkdownImporter.shared.syncFromFolder()

            // Start local API server
            do {
                try await LocalAPIServer.shared.start()
            } catch {
                logger.error("Failed to start API server: \(error.localizedDescription)")
            }

            // Register notification categories and set delegate
            if Bundle.main.bundleIdentifier != nil {
                await MeetingDetector.registerNotificationCategories()
                UNUserNotificationCenter.current().delegate = self
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

            // Check for updates (non-blocking)
            if let release = await UpdateChecker.shared.checkForUpdate() {
                await MainActor.run {
                    showUpdateAlert(release)
                }
            }
        }
    }

    @MainActor
    private func showUpdateAlert(_ release: UpdateChecker.Release) {
        let alert = NSAlert()
        alert.messageText = "Scribe \(release.version) Available"
        alert.informativeText = release.releaseNotes.isEmpty
            ? "A new version of Scribe is available."
            : release.releaseNotes
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.downloadURL)
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
                case .calendarEvent(let title, let eventId, let meetingURL, let participants, let startDate):
                    logger.info("Meeting detected (calendar): \(title)")
                    await showCalendarMeetingAlert(
                        title: title,
                        eventId: eventId,
                        meetingURL: meetingURL,
                        participants: participants,
                        startDate: startDate
                    )
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

    /// Show a rich notification banner for calendar-detected meetings
    @MainActor
    private func showCalendarMeetingAlert(
        title: String,
        eventId: String,
        meetingURL: String?,
        participants: [String],
        startDate: Date
    ) {
        guard !RecordingCoordinator.shared.isRecording else {
            logger.info("Skipping meeting alert — already scribing")
            return
        }

        let timeText = formatTimeUntil(startDate)
        let subtitle = participants.isEmpty ? "" : "with \(participants.count) attendee\(participants.count == 1 ? "" : "s")"

        // Post system notification (respects DND, persists in Notification Center)
        postSystemNotification(title: title, body: "\(timeText) \(subtitle)".trimmingCharacters(in: .whitespaces), meetingTitle: title)

        if let urlString = meetingURL, let url = URL(string: urlString) {
            ScribeNotificationBanner.show(
                title: title,
                subtitle: subtitle,
                timeText: timeText,
                primaryTitle: "Join & Scribe",
                primaryAction: {
                    // Open the meeting URL (Zoom/Meet/Teams)
                    NSWorkspace.shared.open(url)
                    let meetingId = UUID()
                    Task {
                        await RecordingCoordinator.shared.startRecording(meetingId: meetingId, title: title)
                        NotificationCenter.default.post(name: .openMainWindow, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .openMeeting, object: meetingId)
                        }
                    }
                },
                secondaryTitle: "Just Scribe",
                secondaryAction: {
                    let meetingId = UUID()
                    Task {
                        await RecordingCoordinator.shared.startRecording(meetingId: meetingId, title: title)
                        NotificationCenter.default.post(name: .openMainWindow, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: .openMeeting, object: meetingId)
                        }
                    }
                }
            )
        } else {
            // No meeting URL — single action
            showMeetingAlert(title: title, body: subtitle.isEmpty ? "Start scribing?" : subtitle)
        }
    }

    /// Show a floating notification banner in the top-right (like Zoom/Granola)
    @MainActor
    private func showMeetingAlert(title: String, body: String) {
        // Don't show if already scribing
        guard !RecordingCoordinator.shared.isRecording else {
            logger.info("Skipping meeting alert — already scribing")
            return
        }

        // Post system notification (respects DND, persists in Notification Center)
        postSystemNotification(title: title, body: body, meetingTitle: title)

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

    // MARK: - System Notification Center

    /// Post a system notification alongside the custom banner (respects DND, appears in Notification Center)
    private func postSystemNotification(title: String, body: String, meetingTitle: String? = nil) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = "MEETING_DETECTED"
        content.sound = .default
        if let meetingTitle {
            content.userInfo["meetingTitle"] = meetingTitle
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let title = userInfo["meetingTitle"] as? String ?? "Meeting"

        if response.actionIdentifier == "START_RECORDING" {
            Task { @MainActor in
                let meetingId = UUID()
                await RecordingCoordinator.shared.startRecording(meetingId: meetingId, title: title)
                NotificationCenter.default.post(name: .openMainWindow, object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .openMeeting, object: meetingId)
                }
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show system notification even when app is frontmost (banner + sound)
        completionHandler([.banner, .sound])
    }

    /// Format the time remaining until meeting start
    private func formatTimeUntil(_ date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        if seconds <= 0 {
            return "Starting now"
        } else if seconds < 60 {
            return "Starting in <1 min"
        } else {
            let minutes = Int(seconds / 60)
            return "Starting in \(minutes) min"
        }
    }
}
