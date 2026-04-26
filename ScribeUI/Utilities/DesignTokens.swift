import SwiftUI

// MARK: - Mono Design System
// Linear/Raycast lineage. Indigo accent over near-black grays.
// System sans for body, SF Mono for chrome. Built for power users.

// MARK: - Color Extension (hex init)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Adaptive Color Helpers (dark/light with hex values directly)

/// Provides dark/light adaptive colors using the Mono token palette.
/// This avoids needing an asset catalog — colors adapt to system appearance.
public enum MonoColors {
    // Surfaces
    public static let bg = adaptive(dark: "#0a0a0a", light: "#fafaf9")
    public static let bgSubtle = adaptive(dark: "#0f0f0f", light: "#f4f4f3")
    public static let bgElev = adaptive(dark: "#151515", light: "#ffffff")
    public static let bgHover = adaptive(dark: "#1c1c1c", light: "#f0f0ee")
    public static let bgActive = adaptive(dark: "#212121", light: "#e8e8e6")

    // Text
    public static let text = adaptive(dark: "#f2f2f2", light: "#0c0c0c")
    public static let textMuted = adaptive(dark: "#9a9a9a", light: "#6e6e6d")
    public static let textFaint = adaptive(dark: "#5c5c5c", light: "#a3a3a1")

    // Borders
    public static let border = adaptive(dark: "#1f1f1f", light: "#e6e6e4")
    public static let borderStrong = adaptive(dark: "#2a2a2a", light: "#d4d4d2")
    public static let divider = adaptive(dark: "#1a1a1a", light: "#ececea")

    // Accent (Indigo)
    public static let accent = adaptive(dark: "#818cf8", light: "#4f46e5")
    public static let accentText = adaptive(dark: "#c7d2fe", light: "#3730a3")
    public static let accentBg = adaptive(dark: "#1e1b3a", light: "#eef2ff")
    public static let accentBgHover = adaptive(dark: "#2a2750", light: "#e0e7ff")
    public static let accentBorder = adaptive(dark: "#312e81", light: "#c7d2fe")

    // Signal
    public static let live = adaptive(dark: "#fb7185", light: "#e11d48")
    public static let liveBg = adaptive(dark: Color(hex: "#fb7185").opacity(0.10),
                                         light: Color(hex: "#e11d48").opacity(0.08))
    public static let success = adaptive(dark: "#34d399", light: "#059669")
    public static let warn = adaptive(dark: "#fbbf24", light: "#b45309")

    // MARK: - Adaptive builder

    private static func adaptive(dark: String, light: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(Color(hex: dark))
                : NSColor(Color(hex: light))
        })
    }

    private static func adaptive(dark: Color, light: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
    }
}

// MARK: - Typography

public enum MonoFont {
    /// Sans — body text, prose. Maps to Inter / SF Pro Text
    public static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Mono — timestamps, IDs, labels, kbd, paths. Maps to SF Mono
    public static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Type scale (px) — dense, Linear-tier
public enum TypeScale {
    /// 10pt — mono labels, kbd
    public static let xs: CGFloat = 10
    /// 11pt — metadata, captions
    public static let sm: CGFloat = 11
    /// 12pt — body
    public static let base: CGFloat = 12
    /// 13pt — emphasized body
    public static let md: CGFloat = 13
    /// 16pt — section titles
    public static let lg: CGFloat = 16
    /// 18pt — page titles
    public static let xl: CGFloat = 18
    /// 22pt — hero
    public static let xxl: CGFloat = 22
    /// 28pt — display
    public static let xxxl: CGFloat = 28
}

// MARK: - Spacing (4px grid)

public enum Spacing {
    public static let xxxs: CGFloat = 2
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 6
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
    /// 32pt
    public static let xl: CGFloat = 32
    /// 40pt
    public static let xxl: CGFloat = 40
}

// MARK: - Corner Radius — small and tight

public enum Radius {
    public static let sm: CGFloat = 3
    public static let md: CGFloat = 5
    public static let lg: CGFloat = 8
    public static let xl: CGFloat = 12
    public static let pill: CGFloat = 999
}

// MARK: - Animation presets

public enum Anim {
    /// 0.15s ease-out — button press, toggles, hover states
    static let fast = Animation.easeOut(duration: 0.15)
    /// 0.2s ease-out — list selection, state badges, crossfades
    static let standard = Animation.easeOut(duration: 0.2)
    /// 0.3s spring — panels, sheets, onboarding slides
    static let panel = Animation.spring(duration: 0.3, bounce: 0.12)
    /// Per-item stagger delay for batch appearances
    static let stagger: TimeInterval = 0.04

    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Button Styles

/// Subtle scale-down on press for interactive elements
public struct ScribeButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Mono-styled primary button (indigo bg, white text)
public struct MonoPrimaryButtonStyle: ButtonStyle {
    var danger: Bool = false

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MonoFont.sans(size: TypeScale.sm, weight: .medium))
            .padding(.horizontal, Spacing.compact)
            .padding(.vertical, Spacing.xxs)
            .background(danger ? MonoColors.live : MonoColors.accent, in: RoundedRectangle(cornerRadius: Radius.md))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Mono-styled ghost button (transparent bg)
public struct MonoGhostButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MonoFont.sans(size: TypeScale.sm, weight: .medium))
            .padding(.horizontal, Spacing.compact)
            .padding(.vertical, Spacing.xxs)
            .foregroundStyle(MonoColors.textMuted)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Reusable Components

/// Section label — CAPS MONO style
public struct MonoSectionLabel: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .font(MonoFont.mono(size: TypeScale.xs, weight: .semibold))
            .foregroundStyle(MonoColors.textFaint)
            .tracking(0.8)
    }
}

/// Keyboard cap — small mono badge for shortcuts
public struct KbdView: View {
    let label: String

    public init(_ label: String) {
        self.label = label
    }

    public var body: some View {
        Text(label)
            .font(MonoFont.mono(size: TypeScale.xs))
            .foregroundStyle(MonoColors.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(MonoColors.border, lineWidth: 1))
    }
}

/// Tag / pill / status badge
public struct MonoTag: View {
    let text: String
    var color: Color?
    var bgColor: Color?

    public init(_ text: String, color: Color? = nil, bg: Color? = nil) {
        self.text = text
        self.color = color
        self.bgColor = bg
    }

    public var body: some View {
        Text(text)
            .font(MonoFont.mono(size: TypeScale.xs, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(color ?? MonoColors.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(bgColor ?? MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(MonoColors.border, lineWidth: 1))
    }
}

/// Recording dot with pulse animation
public struct RecDot: View {
    var size: CGFloat = 6
    var color: Color = MonoColors.live

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // ~1.2s pulse: opacity 0.55 → 1.0
            let pulse = sin(t * .pi / 0.6) * 0.5 + 0.5
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .opacity(0.55 + 0.45 * pulse)
        }
    }
}

/// Live, continuously animating audio-style waveform for "recording in progress" indication.
/// Driven by TimelineView so it updates without per-frame state changes.
public struct LiveWaveform: View {
    var barCount: Int = 14
    var color: Color = MonoColors.live
    var height: CGFloat = 10
    var barWidth: CGFloat = 1.5
    var spacing: CGFloat = 1.5

    public init(
        barCount: Int = 14,
        color: Color = MonoColors.live,
        height: CGFloat = 10,
        barWidth: CGFloat = 1.5,
        spacing: CGFloat = 1.5
    ) {
        self.barCount = barCount
        self.color = color
        self.height = height
        self.barWidth = barWidth
        self.spacing = spacing
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(color)
                        .frame(width: barWidth, height: barHeight(for: i, t: t))
                }
            }
            .frame(height: height)
        }
    }

    private func barHeight(for index: Int, t: TimeInterval) -> CGFloat {
        let phase = Double(index) * 0.55
        let wave1 = sin(t * 6.0 + phase) * 0.5 + 0.5
        let wave2 = sin(t * 9.7 + phase * 1.7) * 0.5 + 0.5
        let mixed = wave1 * 0.6 + wave2 * 0.4
        let minH = height * 0.25
        return max(2, minH + (height - minH) * CGFloat(mixed))
    }
}

// MARK: - Form Controls (Mono-styled replacements for stock macOS controls)

/// Mono-styled secondary button (subtle border, neutral text) — use for Cancel/Reset/Test type actions
public struct MonoSecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MonoFont.sans(size: TypeScale.sm, weight: .medium))
            .padding(.horizontal, Spacing.compact)
            .padding(.vertical, 5)
            .foregroundStyle(MonoColors.text)
            .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(MonoColors.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Mono-styled text field — flat border, subtle bg, indigo focus ring on focus.
/// Apply via `.textFieldStyle(MonoTextFieldStyle())`.
public struct MonoTextFieldStyle: TextFieldStyle {
    public init() {}
    // swiftlint:disable:next identifier_name
    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(MonoFont.sans(size: TypeScale.base))
            .foregroundStyle(MonoColors.text)
            .textFieldStyle(.plain)
            .padding(.horizontal, Spacing.compact)
            .padding(.vertical, 5)
            .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(MonoColors.border, lineWidth: 1))
    }
}

/// Mono checkbox toggle style. Square with indigo fill + white check when on.
public struct MonoCheckboxToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(configuration.isOn ? MonoColors.accent : MonoColors.bgSubtle)
                        .frame(width: 14, height: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .strokeBorder(configuration.isOn ? MonoColors.accent : MonoColors.borderStrong, lineWidth: 1)
                        )
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                configuration.label
                    .font(MonoFont.sans(size: TypeScale.base))
                    .foregroundStyle(MonoColors.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Mono segmented control — replaces SwiftUI Picker(.segmented).
/// Subtle bg track, indigo fill on selected segment.
public struct MonoSegmentedControl<T: Hashable>: View {
    @Binding var selection: T
    let options: [(label: String, value: T)]

    public init(selection: Binding<T>, options: [(label: String, value: T)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(Anim.fast) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(MonoFont.sans(size: TypeScale.sm, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : MonoColors.textMuted)
                        .padding(.horizontal, Spacing.standard)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(
                            isSelected
                                ? AnyView(RoundedRectangle(cornerRadius: Radius.sm).fill(MonoColors.accent))
                                : AnyView(Color.clear)
                        )
                }
                .buttonStyle(.plain)

                if index < options.count - 1 && !isSelected && options[index + 1].value != selection {
                    Rectangle()
                        .fill(MonoColors.border)
                        .frame(width: 1, height: 14)
                }
            }
        }
        .padding(2)
        .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(MonoColors.border, lineWidth: 1))
    }
}

/// Mono radio list — replaces SwiftUI Picker(.radioGroup).
/// Vertical list of options with circle selectors.
public struct MonoRadioList<T: Hashable>: View {
    @Binding var selection: T
    let options: [(label: String, value: T)]

    public init(selection: Binding<T>, options: [(label: String, value: T)]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(Anim.fast) { selection = option.value }
                } label: {
                    HStack(spacing: Spacing.compact) {
                        ZStack {
                            Circle()
                                .strokeBorder(isSelected ? MonoColors.accent : MonoColors.borderStrong, lineWidth: 1)
                                .frame(width: 14, height: 14)
                            if isSelected {
                                Circle()
                                    .fill(MonoColors.accent)
                                    .frame(width: 7, height: 7)
                            }
                        }
                        Text(option.label)
                            .font(MonoFont.sans(size: TypeScale.base))
                            .foregroundStyle(MonoColors.text)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Mono disclosure triangle — replaces SwiftUI DisclosureGroup.
public struct MonoDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    public init(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Anim.standard) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MonoColors.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title)
                        .font(MonoFont.sans(size: TypeScale.base, weight: .medium))
                        .foregroundStyle(MonoColors.textMuted)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.top, Spacing.compact)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Speaker colors — accent for "you", grays for others
public enum SpeakerColors {
    public static func color(for index: Int?) -> Color {
        guard let index else { return MonoColors.text }
        if index == 0 { return MonoColors.accent }
        let grays: [Color] = [
            Color(hex: "#a3a3a1"),
            Color(hex: "#737372"),
            Color(hex: "#525252"),
            Color(hex: "#404040"),
        ]
        return grays[(index - 1) % grays.count]
    }
}
