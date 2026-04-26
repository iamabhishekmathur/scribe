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

    // Speaker colors now use SpeakerColors.color(for:) from DesignTokens

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
                    .font(MonoFont.mono(size: TypeScale.sm))
                    .foregroundStyle(MonoColors.textFaint)
                TextField("Search transcript...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(MonoFont.mono(size: TypeScale.sm))
                if !searchQuery.isEmpty {
                    Text("\(filteredSegments.count) results")
                        .font(MonoFont.mono(size: TypeScale.xs))
                        .foregroundStyle(MonoColors.textMuted)
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(MonoFont.mono(size: TypeScale.sm))
                            .foregroundStyle(MonoColors.textFaint)
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
                                    .font(MonoFont.mono(size: TypeScale.xs))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        isHidden ? MonoColors.bgSubtle : MonoColors.accentBg,
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(isHidden ? MonoColors.border : MonoColors.accentBorder, lineWidth: 1)
                                    )
                                    .foregroundStyle(isHidden ? MonoColors.textMuted : MonoColors.accentText)
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
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSegments) { segment in
                            // Compact grid row for overlay: speaker · text
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(displayName(for: segment).lowercased()) · \(ScribeDateFormatting.transcriptTime(segment.startTime))")
                                    .font(MonoFont.mono(size: TypeScale.xs))
                                    .foregroundStyle(MonoColors.textMuted)
                                highlightedText(segment.text, query: searchQuery)
                                    .font(MonoFont.sans(size: TypeScale.sm))
                                    .foregroundStyle(MonoColors.text)
                                    .textSelection(.enabled)
                                    .lineSpacing(2)
                            }
                            .padding(.horizontal, Spacing.standard)
                            .padding(.vertical, 6)
                            .id(segment.id)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(MonoColors.divider).frame(height: 1)
                            }
                        }
                    }
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
                        .foregroundStyle(MonoColors.accent)
                        .padding(8)
                        .background(MonoColors.bgElev, in: Circle())
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
                result[attrStart..<attrEnd].backgroundColor = MonoColors.accentBg
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
        SpeakerColors.color(for: index)
    }
}
