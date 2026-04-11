import SwiftUI
import ScribeCore

/// Live transcript view with auto-scroll, iMessage-style layout, and smart speaker names
public struct LiveTranscriptView: View {
    let meetingId: UUID
    @State private var segments: [TranscriptSegment] = []
    @State private var autoScroll = true
    @State private var meeting: MeetingRecord?

    // Speaker color palette (for non-user speakers, 1-indexed)
    private static let speakerColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint
    ]

    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(segments) { segment in
                        let isUser = segment.speakerIndex == 0
                        HStack(alignment: .top, spacing: 0) {

                            if isUser { Spacer(minLength: 40) }

                            VStack(alignment: isUser ? .trailing : .leading, spacing: 1) {
                                Text(displayName(for: segment))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(isUser ? .accentColor : colorForSpeaker(segment.speakerIndex))

                                Text(segment.text)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        isUser ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }

                            if !isUser { Spacer(minLength: 40) }
                        }
                        .id(segment.id)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, Spacing.standard)
                .padding(.vertical, Spacing.compact)
            }
            .onChange(of: segments.count) { _ in
                if autoScroll, let last = segments.last {
                    withAnimation(Anim.standard) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !autoScroll {
                Button {
                    autoScroll = true
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("Resume auto-scroll")
            }
        }
        .task {
            meeting = try? await MeetingStore.shared.getMeeting(id: meetingId)
            await pollTranscripts()
        }
    }

    private func pollTranscripts() async {
        while !Task.isCancelled {
            if let fetched = try? await MeetingStore.shared.getTranscript(meetingId: meetingId) {
                await MainActor.run {
                    if fetched.count != segments.count {
                        segments = fetched
                    }
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func displayName(for segment: TranscriptSegment) -> String {
        guard let idx = segment.speakerIndex else {
            return segment.speaker ?? "Unknown"
        }
        if idx == 0 { return "You" }
        // Try calendar participant names
        if let meeting, let participantsJSON = meeting.participants,
           let data = participantsJSON.data(using: .utf8),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            let pIdx = idx - 1
            if pIdx >= 0 && pIdx < names.count {
                return names[pIdx]
            }
        }
        return "Speaker \(idx)"
    }

    private func colorForSpeaker(_ index: Int?) -> Color {
        guard let index else { return .primary }
        if index == 0 { return .accentColor }
        return Self.speakerColors[(index - 1) % Self.speakerColors.count]
    }
}
