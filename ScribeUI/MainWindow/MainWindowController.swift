import AppKit
import SwiftUI
import ScribeCore
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "Windows")

public extension Notification.Name {
    static let openMainWindow = Notification.Name("com.scribe.openMainWindow")
    static let openSettingsWindow = Notification.Name("com.scribe.openSettingsWindow")
    static let meetingDeleted = Notification.Name("com.scribe.meetingDeleted")
    static let meetingUpdated = Notification.Name("com.scribe.meetingUpdated")
    static let openMeeting = Notification.Name("com.scribe.openMeeting")
}

/// Manages all app windows directly via NSWindow since SPM executables
/// don't support SwiftUI Window/Settings scenes reliably.
@MainActor
public final class MainWindowController {
    public static let shared = MainWindowController()

    private var mainWindow: NSWindow?
    private var appState: AppState?
    private var mainObserver: Any?

    private init() {}

    public func setup(appState: AppState) {
        self.appState = appState

        mainObserver = NotificationCenter.default.addObserver(
            forName: .openMainWindow, object: nil, queue: .main
        ) { [weak self] _ in
            self?.showMain()
        }
    }

    // MARK: - Main Window

    public func showMain() {
        guard let appState else { return }

        if let w = mainWindow, w.isVisible {
            bringToFront(w)
            return
        }

        let view = MainWindowPlaceholder(appState: appState)
        let window = makeWindow(
            content: view,
            title: "Scribe",
            size: NSSize(width: 1050, height: 650),
            autosaveName: "ScribeMainWindow"
        )
        mainWindow = window
        bringToFront(window)
    }

    // MARK: - Helpers

    private func makeWindow<V: View>(
        content: V,
        title: String,
        size: NSSize,
        autosaveName: String,
        resizable: Bool = true
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.setFrameAutosaveName(autosaveName)
        window.isReleasedWhenClosed = false
        return window
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        // Monitor: go back to accessory only when ALL windows are closed
        window.delegate = windowDelegate
    }

    private lazy var windowDelegate: WindowCloseDelegate = {
        WindowCloseDelegate { [weak self] in
            if !(self?.mainWindow?.isVisible ?? false) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }()
}

// MARK: - Window Close Delegate

private class WindowCloseDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        // Small delay to let the window fully close before checking
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            onClose()
        }
    }
}
