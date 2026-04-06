import AppKit
import SwiftUI

/// Floating notification banner that appears in the top-right of the screen,
/// similar to Zoom's "Note-taking is available" banner.
@MainActor
final class ScribeNotificationBanner {
    private static var currentWindow: NSWindow?
    private static var dismissTask: Task<Void, Never>?

    static func show(title: String, subtitle: String, actionTitle: String, action: @escaping () -> Void) {
        // Dismiss any existing banner
        dismiss()

        guard let screen = NSScreen.main else { return }

        let bannerView = BannerView(
            title: title,
            subtitle: subtitle,
            actionTitle: actionTitle,
            onAction: {
                action()
                dismiss()
            },
            onDismiss: {
                dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: bannerView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 60)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .statusBar
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
        let x = screenFrame.maxX - 350
        let y = screenFrame.maxY - 70
        window.setFrameOrigin(NSPoint(x: x, y: y))

        window.alphaValue = 0
        window.orderFrontRegardless()

        // Animate in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 1
        }

        currentWindow = window

        // Auto-dismiss after 10 seconds
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(10))
            await MainActor.run { dismiss() }
        }
    }

    static func dismiss() {
        dismissTask?.cancel()
        guard let window = currentWindow else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
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
    let actionTitle: String
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(actionTitle) {
                onAction()
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}
