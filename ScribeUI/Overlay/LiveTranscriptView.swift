import SwiftUI
import ScribeCore

/// Live transcript view with auto-scroll, search, speaker filter, and iMessage-style layout
public struct LiveTranscriptView: View {
    let meetingId: UUID
    @State private var segments: [TranscriptSegment] = []
    @State private var autoScroll = true
    @State private var meeting: MeetingRecord?
    @State private var searchQuery = ""
    @State private var hiddenSpeakers: Set<Int> = []

    // Speaker color palette (for non-user speakers, 1-indexed)
    private static let speakerColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint
    ]

    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }

    /// Group consecutive same-speaker segments into single display entries
    private var groupedSegments: [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for seg in segments {
            if var last = result.last,
               last.speakerIndex == seg.speakerIndex,
               last.speaker == seg.speaker {
                // Merge into previous
                result[result.count - 1].text += " " + seg.text
                result[result.count - 1].endTime = seg.endTime
            } else {
                result.append(seg)
            }
        }
        return result
    }

    private var filteredSegments: [TranscriptSegment] {
        groupedSegments.filter { seg in
            // Speaker filter
            if let idx = seg.speakerIndex, hiddenSpeakers.contains(idx) { return false }
            // Text search
            if !searchQuery.isEmpty {
                return seg.text.localizedCaseInsensitiveContains(searchQuery)
            }
            return true
        }
    }

    private var activeSpeakers: [Int] {
        Array(Set(segments.compactMap(\.speakerIndex))).sorted()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                TextField("Search transcript...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchQuery.isEmpty {
                    Text("\(filteredSegments.count) results")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.standard)
            .padding(.vertical, 4)

            // Speaker filter chips
            if activeSpeakers.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(activeSpeakers, id: \.self) { idx in
                            let name = speakerName(for: idx)
                            let isHidden = hiddenSpeakers.contains(idx)
                            Button {
                                if isHidden { hiddenSpeakers.remove(idx) }
                                else { hiddenSpeakers.insert(idx) }
                            } label: {
                                Text(name)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        isHidden ? Color.clear : colorForSpeaker(idx).opacity(0.15),
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(isHidden ? Color.secondary.opacity(0.3) : .clear, lineWidth: 1)
                                    )
                                    .foregroundStyle(isHidden ? .secondary : colorForSpeaker(idx))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.standard)
                    .padding(.bottom, 4)
                }
            }

            Divider()

            // Transcript
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredSegments) { segment in
                            let isUser = segment.speakerIndex == 0
                            HStack(alignment: .top, spacing: 0) {
                                if isUser { Spacer(minLength: 40) }

                                VStack(alignment: isUser ? .trailing : .leading, spacing: 1) {
                                    Text(displayName(for: segment))
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(isUser ? .accentColor : colorForSpeaker(segment.speakerIndex))

                                    highlightedText(segment.text, query: searchQuery)
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
                    if autoScroll && searchQuery.isEmpty, let last = segments.last {
                        withAnimation(Anim.standard) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !autoScroll && searchQuery.isEmpty {
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

    // MARK: - Highlighted Text

    @ViewBuilder
    private func highlightedText(_ text: String, query: String) -> some View {
        if query.isEmpty {
            Text(text)
        } else {
            Text(buildHighlighted(text, query: query))
        }
    }

    private func buildHighlighted(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        let lower = text.lowercased()
        let queryLower = query.lowercased()
        var searchStart = lower.startIndex
        while let range = lower.range(of: queryLower, range: searchStart..<lower.endIndex) {
            let attrStart = AttributedString.Index(range.lowerBound, within: result)
            let attrEnd = AttributedString.Index(range.upperBound, within: result)
            if let attrStart, let attrEnd {
                result[attrStart..<attrEnd].backgroundColor = .yellow.opacity(0.3)
            }
            searchStart = range.upperBound
        }
        return result
    }

    // MARK: - Data

    private func pollTranscripts() async {
        while !Task.isCancelled {
            if let fetched = try? await MeetingStore.shared.getTranscript(meetingId: meetingId) {
                await MainActor.run {
                    // Always update — segments may change content (interim → final)
                    // even when count stays the same
                    segments = fetched
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func speakerName(for index: Int) -> String {
        if index == 0 { return "You" }
        if let meeting, let participantsJSON = meeting.participants,
           let data = participantsJSON.data(using: .utf8),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            let pIdx = index - 1
            if pIdx >= 0 && pIdx < names.count { return names[pIdx] }
        }
        return "Speaker \(index)"
    }

    private func displayName(for segment: TranscriptSegment) -> String {
        guard let idx = segment.speakerIndex else {
            return segment.speaker ?? "Unknown"
        }
        return speakerName(for: idx)
    }

    private func colorForSpeaker(_ index: Int?) -> Color {
        guard let index else { return .primary }
        if index == 0 { return .accentColor }
        return Self.speakerColors[(index - 1) % Self.speakerColors.count]
    }
}
