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
            Picker("", selection: $selectedTab) {
                ForEach(OverlayTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

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
        .background(.ultraThinMaterial)
    }

    private var overlayHeader: some View {
        HStack {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text("Recording")
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Text(timerText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var timerText: String {
        let elapsed = Date().timeIntervalSince(appState.recordingState == .recording ? Date() : Date())
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
