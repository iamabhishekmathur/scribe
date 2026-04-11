import SwiftUI

/// Standardized spacing tokens for consistent UI across all Scribe surfaces
public enum Spacing {
    /// 8pt — tight spacing for dense UI elements
    public static let compact: CGFloat = 8
    /// 12pt — standard spacing for most UI elements
    public static let standard: CGFloat = 12
    /// 16pt — comfortable spacing for section separation
    public static let comfortable: CGFloat = 16
    /// 20pt — spacious padding for content areas
    public static let spacious: CGFloat = 20
    /// 24pt — generous padding for top-level content
    public static let generous: CGFloat = 24
}

/// Animation presets — single source of truth for all Scribe transitions
public enum Anim {
    /// 0.15s ease-out — button press, toggles, hover states
    static let fast = Animation.easeOut(duration: 0.15)
    /// 0.2s ease-out — list selection, state badges, crossfades
    static let standard = Animation.easeOut(duration: 0.2)
    /// 0.3s spring — panels, sheets, onboarding slides
    static let panel = Animation.spring(duration: 0.3, bounce: 0.12)
    /// Per-item stagger delay for batch appearances
    static let stagger: TimeInterval = 0.04

    /// Returns nil when Reduce Motion is enabled, disabling the animation
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Subtle scale-down on press for interactive pills/capsules
public struct ScribeButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
