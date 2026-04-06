import AVFoundation
import ScreenCaptureKit
import EventKit
import UserNotifications
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "Permissions")

@MainActor
public final class PermissionsManager: ObservableObject {
    public static let shared = PermissionsManager()

    @Published public var microphoneGranted: Bool = false
    @Published public var screenRecordingGranted: Bool = false
    @Published public var calendarGranted: Bool = false
    @Published public var notificationsGranted: Bool = false

    /// Whether the app has a bundle identifier (false for SPM executables)
    public let hasBundleId: Bool

    private init() {
        hasBundleId = Bundle.main.bundleIdentifier != nil
    }

    public func checkAll() async {
        await checkMicrophone()
        await checkScreenRecording()
        await checkCalendar()
        await checkNotifications()
    }

    public func checkMicrophone() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            microphoneGranted = false
        }
        logger.info("Microphone: \(self.microphoneGranted)")
    }

    public func checkScreenRecording() async {
        // SCShareableContent and CGPreflightScreenCaptureAccess both fail for
        // unsigned SPM executables even when permission IS granted in System Settings.
        // Use a persisted flag: set to true after first successful audio capture.
        // Users can also manually mark it via the UI.
        let wasGrantedBefore = UserDefaults.standard.bool(forKey: "screenRecordingEverGranted")
        if wasGrantedBefore {
            screenRecordingGranted = true
            logger.info("Screen recording: true (previously verified)")
            return
        }

        // Try the API check — works for signed .app bundles
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            screenRecordingGranted = !content.displays.isEmpty
            if screenRecordingGranted {
                UserDefaults.standard.set(true, forKey: "screenRecordingEverGranted")
            }
        } catch {
            // For unsigned apps, assume granted if listed in System Settings
            // (we can't detect this programmatically)
            screenRecordingGranted = false
        }
        logger.info("Screen recording: \(self.screenRecordingGranted)")
    }

    /// Call this when audio capture succeeds to persist the permission state
    public func markScreenRecordingGranted() {
        screenRecordingGranted = true
        UserDefaults.standard.set(true, forKey: "screenRecordingEverGranted")
        logger.info("Screen recording marked as granted (capture succeeded)")
    }

    public func checkCalendar() async {
        let store = EKEventStore()
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            calendarGranted = true
        case .notDetermined:
            do {
                if #available(macOS 14.0, *) {
                    calendarGranted = try await store.requestFullAccessToEvents()
                } else {
                    calendarGranted = try await store.requestAccess(to: .event)
                }
            } catch {
                calendarGranted = false
            }
        default:
            calendarGranted = false
        }
        logger.info("Calendar: \(self.calendarGranted)")
    }

    public func checkNotifications() async {
        guard hasBundleId else {
            // Can't use UNUserNotificationCenter without a bundle identifier.
            // Mark as unavailable rather than silently failing.
            notificationsGranted = false
            logger.info("Notifications: skipped (no bundle ID)")
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            notificationsGranted = true
        case .notDetermined:
            do {
                notificationsGranted = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                notificationsGranted = false
            }
        default:
            notificationsGranted = false
        }
        logger.info("Notifications: \(self.notificationsGranted)")
    }

    public func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    public func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
    }

    public var allGranted: Bool {
        microphoneGranted && screenRecordingGranted && calendarGranted && (notificationsGranted || !hasBundleId)
    }
}
