import AppKit
import SwiftUI
import ScribeCore

/// Floating NSPanel that doesn't steal focus during meetings.
/// Hidden from screen share via `window.sharingType = .none`.
public class FloatingOverlayWindow: NSPanel {
    public init(contentRect: NSRect = NSRect(x: 0, y: 0, width: 320, height: 480)) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        // Hidden from screen sharing
        sharingType = .none

        // Minimum size
        minSize = NSSize(width: 280, height: 300)
    }

    /// Position the overlay at the right side of the screen
    public func positionAtRight() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - frame.width - 16
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    // Don't become key window — keeps focus on meeting app
    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }
}

/// Manages the overlay window lifecycle
@MainActor
public final class OverlayWindowController: ObservableObject {
    private var window: FloatingOverlayWindow?
    @Published public var isVisible = false

    public init() {}

    public func show(appState: AppState, meetingId: UUID) {
        if window == nil {
            let overlay = FloatingOverlayWindow()
            let view = OverlayContentView(appState: appState, meetingId: meetingId)
            overlay.contentView = NSHostingView(rootView: view)
            overlay.positionAtRight()
            self.window = overlay
        }
        window?.alphaValue = 0
        window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.window?.animator().alphaValue = 1
        }
        isVisible = true
    }

    public func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
        })
        isVisible = false
    }

    public func close() {
        window?.close()
        window = nil
        isVisible = false
    }
}
