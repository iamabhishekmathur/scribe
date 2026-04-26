import SwiftUI
import ScribeCore

/// Root view for the floating overlay during meetings
struct OverlayContentView: View {
    @ObservedObject var appState: AppState
    let meetingId: UUID
    @State private var selectedTab: OverlayTab = .transcript

    enum OverlayTab: String, CaseIterable {
        case transcript = "Transcript"
        case notes = "Notes"
        case chat = "AI Chat"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            overlayHeader

            // Tab bar
            HStack(spacing: 0) {
                ForEach(OverlayTab.allCases, id: \.self) { tab in
                    let isActive = selectedTab == tab
                    Button {
                        withAnimation(Anim.fast) { selectedTab = tab }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab == .transcript ? "waveform" : (tab == .notes ? "pencil" : "sparkles"))
                                .font(.system(size: 10))
                                .foregroundStyle(isActive ? MonoColors.accent : MonoColors.textFaint)
                            Text(tab.rawValue.lowercased())
                                .font(MonoFont.mono(size: 10.5, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? MonoColors.text : MonoColors.textFaint)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isActive ? MonoColors.accentBg : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
                        .padding(.horizontal, 4)
                        .overlay(alignment: .bottom) {
                            if isActive {
                                Rectangle().fill(MonoColors.accent).frame(height: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MonoColors.divider).frame(height: 1)
            }

            // Content
            switch selectedTab {
            case .transcript:
                LiveTranscriptView(meetingId: meetingId)
            case .notes:
                NoteInputView(meetingId: meetingId)
            case .chat:
                AIChatView(meetingId: meetingId)
            }
        }
        .frame(minWidth: 280, minHeight: 300)
        .background(MonoColors.bgElev)
    }

    private var overlayHeader: some View {
        HStack {
            RecDot(size: 6, color: MonoColors.live)
                .accessibilityHidden(true)
            Text("REC")
                .font(MonoFont.mono(size: TypeScale.xs, weight: .bold))
                .foregroundStyle(MonoColors.live)
            Spacer()
            Text(timerText)
                .font(MonoFont.mono(size: TypeScale.xs))
                .foregroundStyle(MonoColors.textMuted)
        }
        .padding(.horizontal, Spacing.standard)
        .padding(.top, Spacing.compact)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording in progress")
    }

    private var timerText: String {
        let elapsed = Date().timeIntervalSince(appState.recordingState == .recording ? Date() : Date())
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
