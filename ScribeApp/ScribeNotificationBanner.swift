import AppKit
import SwiftUI

/// Floating notification banner that appears in the top-right of the screen,
/// similar to Zoom's "Note-taking is available" banner.
@MainActor
final class ScribeNotificationBanner {
    private static var currentWindow: NSWindow?
    private static var dismissTask: Task<Void, Never>?

    /// Simple single-action banner (existing API)
    static func show(title: String, subtitle: String, actionTitle: String, action: @escaping () -> Void) {
        showBanner(
            title: title,
            subtitle: subtitle,
            timeText: nil,
            primaryTitle: actionTitle,
            primaryAction: action,
            secondaryTitle: nil,
            secondaryAction: nil,
            autoDismissSeconds: 10
        )
    }

    /// Rich two-action banner with time display (for calendar-triggered notifications)
    static func show(
        title: String,
        subtitle: String,
        timeText: String?,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) {
        showBanner(
            title: title,
            subtitle: subtitle,
            timeText: timeText,
            primaryTitle: primaryTitle,
            primaryAction: primaryAction,
            secondaryTitle: secondaryTitle,
            secondaryAction: secondaryAction,
            autoDismissSeconds: 30
        )
    }

    private static func showBanner(
        title: String,
        subtitle: String,
        timeText: String?,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?,
        autoDismissSeconds: Int
    ) {
        dismiss()

        // Respect Do Not Disturb / Focus modes — suppress banner when Focus is active
        if isFocusModeActive() { return }

        guard let screen = NSScreen.main else { return }

        let hasSecondary = secondaryTitle != nil && secondaryAction != nil
        let bannerWidth: CGFloat = hasSecondary ? 380 : 340
        let bannerHeight: CGFloat = 60

        let bannerView = BannerView(
            title: title,
            subtitle: subtitle,
            timeText: timeText,
            primaryTitle: primaryTitle,
            onPrimaryAction: {
                primaryAction()
                dismiss()
            },
            secondaryTitle: secondaryTitle,
            onSecondaryAction: secondaryAction.map { action in
                { action(); dismiss() }
            },
            onDismiss: {
                dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: bannerView)
        hostingView.frame = NSRect(x: 0, y: 0, width: bannerWidth, height: bannerHeight)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: bannerWidth, height: bannerHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentView = hostingView
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Position top-right of screen
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - bannerWidth - 10
        let y = screenFrame.maxY - 70
        window.setFrameOrigin(NSPoint(x: x, y: y))

        // Position slightly above final position for slide-down entry
        let finalOrigin = window.frame.origin
        window.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y + 10))
        window.alphaValue = 0
        window.orderFrontRegardless()

        // Animate in — ease-out slide down + fade
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrameOrigin(finalOrigin)
        }

        currentWindow = window

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(autoDismissSeconds))
            await MainActor.run { dismiss() }
        }
    }

    /// Check if macOS Focus/DND is active by querying the DND assertions preference
    private static func isFocusModeActive() -> Bool {
        // Check via UserDefaults for the DND mirror preference (public API not available)
        // The com.apple.controlcenter "NSDoNotDisturb" key reflects Focus state
        let dndDefaults = UserDefaults(suiteName: "com.apple.controlcenter")
        return dndDefaults?.bool(forKey: "NSDoNotDisturb") ?? false
    }

    static func dismiss() {
        dismissTask?.cancel()
        guard let window = currentWindow else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
        currentWindow = nil
    }
}

// MARK: - Banner SwiftUI View

private struct BannerView: View {
    let title: String
    let subtitle: String
    let timeText: String?
    let primaryTitle: String
    let onPrimaryAction: () -> Void
    let secondaryTitle: String?
    let onSecondaryAction: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if let timeText {
                        Spacer()
                        Text(timeText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fontWeight(.medium)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if timeText == nil {
                Spacer()
            }

            if let secondaryTitle, let onSecondaryAction {
                Button(secondaryTitle) {
                    onSecondaryAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(primaryTitle) {
                onPrimaryAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }
}
