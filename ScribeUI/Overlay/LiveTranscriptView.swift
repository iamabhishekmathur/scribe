import SwiftUI
import ScribeCore

/// Live transcript view with auto-scroll and speaker colors
public struct LiveTranscriptView: View {
    let meetingId: UUID
    @State private var segments: [TranscriptSegment] = []
    @State private var autoScroll = true

    // Speaker color palette
    private static let speakerColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint
    ]

    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(segments) { segment in
                        TranscriptSegmentRow(
                            segment: segment,
                            color: colorForSpeaker(segment.speakerIndex)
                        )
                        .id(segment.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: segments.count) { _ in
                if autoScroll, let last = segments.last {
                    withAnimation(.easeOut(duration: 0.2)) {
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
            }
        }
        .task {
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

    private func colorForSpeaker(_ index: Int?) -> Color {
        guard let index else { return .primary }
        return Self.speakerColors[index % Self.speakerColors.count]
    }
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let speaker = segment.speaker {
                Text(speaker)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            Text(segment.text)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}
