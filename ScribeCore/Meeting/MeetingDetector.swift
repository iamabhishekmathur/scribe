import Foundation
import UserNotifications
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "MeetingDetector")

/// Orchestrates meeting detection from multiple signals:
/// calendar events, running processes, and audio activity.
public actor MeetingDetector {
    private let calendarDetector = CalendarDetector()
    private let processDetector = ProcessDetector()
    private let audioDetector = AudioActivityDetector()

    private var calendarTask: Task<Void, Never>?
    private var processTask: Task<Void, Never>?
    private var audioCheckTask: Task<Void, Never>?
    private var _isMonitoring = false
    private var detectionContinuation: AsyncStream<DetectionEvent>.Continuation?

    public var isMonitoring: Bool { _isMonitoring }

    public static let shared = MeetingDetector()
    private init() {}

    public enum DetectionEvent: Sendable {
        case calendarEvent(title: String, eventId: String, meetingURL: String?, participants: [String])
        case appLaunched(appName: String, bundleId: String)
        case appClosed(appName: String, bundleId: String)
        case audioActivity
        case browserMeeting  // Google Meet detected via browser + audio heuristic
    }

    /// Start monitoring for meetings. Returns a stream of detection events.
    public func startMonitoring() async -> AsyncStream<DetectionEvent> {
        guard !_isMonitoring else {
            return AsyncStream { $0.finish() }
        }

        _isMonitoring = true

        let stream = AsyncStream<DetectionEvent> { continuation in
            self.detectionContinuation = continuation
        }

        // Monitor calendar
        let calendarStream = await calendarDetector.start()
        calendarTask = Task { [weak self] in
            for await meeting in calendarStream {
                guard let self, !Task.isCancelled else { break }
                logger.info("Calendar event detected: \(meeting.title)")
                await self.emitEvent(.calendarEvent(
                    title: meeting.title,
                    eventId: meeting.eventId,
                    meetingURL: meeting.meetingURL,
                    participants: meeting.participants
                ))
            }
        }

        // Monitor processes (dedicated meeting apps + close detection)
        let processStream = await processDetector.start()
        processTask = Task { [weak self] in
            for await event in processStream {
                guard let self, !Task.isCancelled else { break }
                switch event {
                case .meetingStarted(let app):
                    logger.info("Meeting STARTED: \(app.appName)")
                    await self.emitEvent(.appLaunched(appName: app.appName, bundleId: app.bundleId))
                case .meetingEnded(let app):
                    logger.info("Meeting ENDED: \(app.appName)")
                    await self.emitEvent(.appClosed(appName: app.appName, bundleId: app.bundleId))
                }
            }
        }

        // Monitor for browser-based meetings (Google Meet) via audio activity
        audioCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                // If a browser is frontmost and audio activity is detected, likely Google Meet
                let browserFront = await self.processDetector.isBrowserFrontmost()
                let audioActive = await self.audioDetector.isMeetingLikeActivity
                if browserFront && audioActive {
                    logger.info("Browser meeting detected (Google Meet heuristic)")
                    await self.emitEvent(.browserMeeting)
                    await self.audioDetector.reset()
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }

        return stream
    }

    /// Stop all monitoring
    public func stopMonitoring() async {
        calendarTask?.cancel()
        processTask?.cancel()
        audioCheckTask?.cancel()
        calendarTask = nil
        processTask = nil
        audioCheckTask = nil
        await calendarDetector.stop()
        await processDetector.stop()
        await audioDetector.reset()
        detectionContinuation?.finish()
        detectionContinuation = nil
        _isMonitoring = false
    }

    /// Update audio levels (called from audio capture pipeline)
    public func updateAudioLevels(micRMS: Float, systemRMS: Float) async {
        await audioDetector.updateMicLevel(micRMS)
        await audioDetector.updateSystemLevel(systemRMS)
    }

    private func emitEvent(_ event: DetectionEvent) {
        detectionContinuation?.yield(event)
    }

    /// Register notification categories (call once at app startup)
    public static func registerNotificationCategories() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let startAction = UNNotificationAction(identifier: "START_RECORDING", title: "Start Recording", options: [.foreground])
        let dismissAction = UNNotificationAction(identifier: "DISMISS", title: "Dismiss", options: [.destructive])
        let category = UNNotificationCategory(identifier: "MEETING_DETECTED", actions: [startAction, dismissAction], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
