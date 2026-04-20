import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "ProcessDetector")

/// Detects running meeting applications (Zoom, Teams, etc.) via NSWorkspace.
/// Also detects when meeting apps close.
public actor ProcessDetector {
    private var pollTask: Task<Void, Never>?
    private var previouslyRunning: Set<String> = []

    /// Bundle identifiers of known meeting apps
    private static let meetingApps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "us.zoom.videomeeting": "Zoom",
        "com.microsoft.teams": "Microsoft Teams",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.cisco.webex.meetings": "Webex",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.tinyspeck.slackmacgap2": "Slack",
        "com.google.Chrome": "Google Chrome",
        "com.apple.Safari": "Safari",
        "com.brave.Browser": "Brave Browser",
        "org.mozilla.firefox": "Firefox",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.google.Chrome.canary": "Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.operasoftware.Opera": "Opera",
    ]

    /// Apps that are definitely meeting-only (not browsers)
    private static let dedicatedMeetingApps: Set<String> = [
        "us.zoom.xos",
        "us.zoom.videomeeting",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.cisco.webex.meetings",
        "com.tinyspeck.slackmacgap",
        "com.tinyspeck.slackmacgap2",
    ]

    /// Zoom meeting helper process — present only when a meeting is active
    private static let zoomMeetingProcesses = ["CptHost", "zMeetingPro"]

    /// Browser bundle IDs — Google Meet runs in these
    private static let browsers: Set<String> = [
        "com.google.Chrome", "com.apple.Safari", "com.brave.Browser",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.operasoftware.Opera",
    ]

    private var previouslyInMeeting = false

    public init() {}

    public enum DetectionEvent: Sendable {
        case meetingStarted(DetectedApp)
        case meetingEnded(DetectedApp)
    }

    public struct DetectedApp: Sendable {
        public let bundleId: String
        public let appName: String
        public let isDedicatedMeetingApp: Bool
    }

    /// Start watching for active meetings (not just app launches).
    public func start(pollInterval: TimeInterval = 5) -> AsyncStream<DetectionEvent> {
        // Snapshot current state
        previouslyRunning = Set(
            NSWorkspace.shared.runningApplications
                .compactMap(\.bundleIdentifier)
                .filter { Self.dedicatedMeetingApps.contains($0) }
        )
        previouslyInMeeting = isInActiveMeeting()

        return AsyncStream { continuation in
            self.pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    if let self {
                        let events = await self.checkMeetingState()
                        for event in events {
                            continuation.yield(event)
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

    /// Check if any browser is the frontmost app (potential Google Meet)
    public func isBrowserFrontmost() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else { return false }
        return Self.browsers.contains(bundleId)
    }

    /// Get currently running dedicated meeting apps
    public func getRunningMeetingApps() -> [DetectedApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleId = app.bundleIdentifier,
                  Self.dedicatedMeetingApps.contains(bundleId),
                  let name = Self.meetingApps[bundleId] else { return nil }
            return DetectedApp(bundleId: bundleId, appName: name, isDedicatedMeetingApp: true)
        }
    }

    /// Check if user is currently in an active meeting (not just app running)
    private func isInActiveMeeting() -> Bool {
        let runningNames = NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }
        let runningBundleIds = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })

        // Zoom: check for CptHost process (only present during active meeting)
        if runningBundleIds.contains("us.zoom.xos") || runningBundleIds.contains("us.zoom.videomeeting") {
            for name in runningNames {
                if Self.zoomMeetingProcesses.contains(name) {
                    return true
                }
            }
            // Also check via shell for CptHost (it may not show in NSWorkspace)
            let task = Process()
            task.launchPath = "/usr/bin/pgrep"
            task.arguments = ["-x", "CptHost"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 { return true }
        }

        // Teams: check if Teams is running (Teams quits its meeting window but keeps running;
        // for now, treat Teams as "in meeting" if it's the frontmost app)
        if runningBundleIds.contains("com.microsoft.teams") || runningBundleIds.contains("com.microsoft.teams2") {
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               front.contains("teams") {
                return true
            }
        }

        // WebEx
        if runningBundleIds.contains("com.cisco.webexmeetingsapp") || runningBundleIds.contains("com.cisco.webex.meetings") {
            return true
        }

        // Slack: detect huddles/calls — Slack is frontmost (similar to Teams heuristic)
        if runningBundleIds.contains("com.tinyspeck.slackmacgap") || runningBundleIds.contains("com.tinyspeck.slackmacgap2") {
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               front.contains("slackmacgap") {
                return true
            }
        }

        return false
    }

    /// Detect meeting start/end transitions
    private func checkMeetingState() -> [DetectionEvent] {
        let currentlyInMeeting = isInActiveMeeting()
        var events: [DetectionEvent] = []

        if currentlyInMeeting && !previouslyInMeeting {
            // Meeting just started
            let app = identifyActiveMeetingApp()
            events.append(.meetingStarted(app))
            logger.info("Meeting STARTED in \(app.appName)")
        } else if !currentlyInMeeting && previouslyInMeeting {
            // Meeting just ended
            let app = identifyActiveMeetingApp()
            events.append(.meetingEnded(app))
            logger.info("Meeting ENDED in \(app.appName)")
        }

        previouslyInMeeting = currentlyInMeeting
        return events
    }

    /// Figure out which meeting app is currently active
    private func identifyActiveMeetingApp() -> DetectedApp {
        let runningBundleIds = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })

        for bundleId in Self.dedicatedMeetingApps {
            if runningBundleIds.contains(bundleId), let name = Self.meetingApps[bundleId] {
                return DetectedApp(bundleId: bundleId, appName: name, isDedicatedMeetingApp: true)
            }
        }

        return DetectedApp(bundleId: "unknown", appName: "Unknown", isDedicatedMeetingApp: false)
    }
}
