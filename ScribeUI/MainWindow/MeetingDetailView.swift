import SwiftUI
import ScribeCore

/// Meeting detail: tabbed view matching Mono design.
/// Tabs: Transcript | Notes | Summary | Ask Scribe
/// Bottom: command bar with › prompt
public struct MeetingDetailView: View {
    let meetingId: UUID
    @State private var meeting: MeetingRecord?
    @State private var editedTitle = ""
    @State private var selectedTab: DetailTab = .transcript
    @State private var noteContent = ""
    @State private var chatInput = ""
    @State private var chatMessages: [ChatMsg] = []
    @State private var isChatLoading = false
    @State private var isSummarizing = false
    @State private var chatService = ChatService()
    @State private var transcriptSegments: [TranscriptSegment] = []
    @State private var summaries: [AISummary] = []
    @State private var transcriptPollTask: Task<Void, Never>?
    @State private var detailFolders: [Folder] = []
    @State private var errorMessage: String?
    @State private var showSummaryPicker = false
    @State private var selectedTemplate: SummaryTemplate = .general
    @FocusState private var titleFieldFocused: Bool

    @ObservedObject private var coordinator = RecordingCoordinator.shared

    enum DetailTab: String, CaseIterable {
        case transcript, notes, summary, chat
    }

    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }

    private var isActivelyScribing: Bool {
        coordinator.isRecording && coordinator.currentMeetingId == meetingId
    }

    private var isComplete: Bool {
        meeting?.state == "complete"
    }

    private var groupedTranscript: [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for seg in transcriptSegments {
            if let last = result.last,
               last.speakerIndex == seg.speakerIndex,
               last.speaker == seg.speaker {
                result[result.count - 1].text += " " + seg.text
                result[result.count - 1].endTime = seg.endTime
            } else {
                result.append(seg)
            }
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let meeting {
                // MARK: — Detail Header (design: padding 14px 18px 0)
                detailHeader(meeting)

                // MARK: — Tab content
                switch selectedTab {
                case .transcript:
                    transcriptTabContent
                case .notes:
                    notesTabContent
                case .summary:
                    summaryTabContent
                case .chat:
                    chatTabContent
                }

                // MARK: — Command bar (always at bottom)
                commandBar
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MonoColors.bg)
        .errorBanner($errorMessage)
        .task { await loadAll(); startPollingIfNeeded() }
        .onChange(of: meetingId) { _ in
            transcriptPollTask?.cancel()
            Task { await loadAll(); startPollingIfNeeded() }
        }
        .onChange(of: coordinator.isRecording) { _ in
            transcriptPollTask?.cancel()
            startPollingIfNeeded()
            Task { await loadAll() }
        }
        .onChange(of: coordinator.currentMeetingId) { _ in
            transcriptPollTask?.cancel()
            startPollingIfNeeded()
        }
        .onDisappear { transcriptPollTask?.cancel() }
    }

    // MARK: - Detail Header

    private func detailHeader(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Recording indicator row
            if isActivelyScribing {
                HStack(spacing: 8) {
                    RecDot(size: 6, color: MonoColors.live)
                    Text("REC")
                        .font(MonoFont.mono(size: TypeScale.xs, weight: .bold))
                        .foregroundStyle(MonoColors.live)
                        .tracking(0.8)
                    LiveWaveform(barCount: 14, color: MonoColors.live, height: 10)
                    Text("·")
                        .font(MonoFont.mono(size: TypeScale.xs))
                        .foregroundStyle(MonoColors.textMuted)
                    Text("started \(formatDate(meeting.startTime))")
                        .font(MonoFont.mono(size: TypeScale.xs))
                        .foregroundStyle(MonoColors.textMuted)
                    Spacer()
                }
                .padding(.bottom, 8)
            }

            // Title row
            HStack(alignment: .top, spacing: 8) {
                TextField("Meeting title", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .font(MonoFont.sans(size: TypeScale.xl, weight: .bold))
                    .focused($titleFieldFocused)
                    .onSubmit { saveTitle() }
                    .onChange(of: titleFieldFocused) { focused in
                        if !focused { saveTitle() }
                    }
                    .onHover { hovering in
                        if hovering { NSCursor.iBeam.push() } else { NSCursor.pop() }
                    }

                Spacer()

                Button {
                    Task {
                        do {
                            try await MeetingStore.shared.deleteMeeting(id: meetingId)
                            NotificationCenter.default.post(name: .meetingDeleted, object: meetingId)
                        } catch { errorMessage = "Failed to delete meeting" }
                    }
                } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                        .foregroundStyle(MonoColors.textFaint)
                }
                .buttonStyle(.plain)
                .help("Delete meeting")
            }

            // Metadata line: folder/name · source · duration · words — mono 10.5px with · separators
            HStack(spacing: 0) {
                let meta = buildMeta(meeting)
                ForEach(Array(meta.enumerated()), id: \.offset) { i, m in
                    if i > 0 {
                        Text(" · ")
                            .font(MonoFont.mono(size: 10.5))
                            .foregroundStyle(MonoColors.textFaint)
                    }
                    Text(m)
                        .font(MonoFont.mono(size: 10.5))
                        .foregroundStyle(MonoColors.textMuted)
                }
            }
            .padding(.top, 6)

            // Tab bar
            HStack(spacing: 2) {
                tabButton(.transcript, label: "Transcript", icon: "waveform")
                tabButton(.notes, label: "Notes", icon: "pencil",
                          count: noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : nil)
                tabButton(.summary, label: "Summary", icon: "sparkles")
                tabButton(.chat, label: "Ask Scribe", icon: "bubble.left")
                Spacer()

                // Stop button when recording
                if isActivelyScribing {
                    Button {
                        Task { await coordinator.stopRecording(); await loadAll() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill").font(.system(size: 8))
                            Text("End")
                                .font(MonoFont.mono(size: TypeScale.xs, weight: .semibold))
                            Text("⇧⌘E")
                                .font(MonoFont.mono(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: Radius.sm))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MonoColors.live, in: RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("e", modifiers: [.shift, .command])
                    .help("End meeting (⇧⌘E)")
                }

                // Generate summary button
                if !isActivelyScribing && meeting.state == "ended" && summaries.isEmpty {
                    Button {
                        selectedTemplate = SummaryTemplate.find(AppSettings.shared.defaultTemplateId)
                        showSummaryPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles").font(.system(size: 9))
                            Text("Generate")
                                .font(MonoFont.mono(size: TypeScale.xs, weight: .semibold))
                        }
                        .foregroundStyle(MonoColors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MonoColors.accentBg, in: RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSummaryPicker, arrowEdge: .top) {
                        summaryTypePicker
                    }
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .overlay(alignment: .bottom) {
            // 1px divider at bottom of header
            Rectangle().fill(MonoColors.divider).frame(height: 1)
        }
    }

    private func tabButton(_ tab: DetailTab, label: String, icon: String, count: Int? = nil) -> some View {
        let isActive = selectedTab == tab
        return Button {
            withAnimation(Anim.fast) { selectedTab = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? MonoColors.accent : MonoColors.textFaint)
                Text(label)
                    .font(MonoFont.sans(size: 11.5, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? MonoColors.text : MonoColors.textFaint)
                if let count {
                    Text("\(count)")
                        .font(MonoFont.mono(size: TypeScale.xs))
                        .foregroundStyle(MonoColors.textFaint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? MonoColors.accentBg : .clear, in: RoundedRectangle(cornerRadius: Radius.sm))
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(MonoColors.accent)
                        .frame(height: 2)
                        .offset(y: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func buildMeta(_ meeting: MeetingRecord) -> [String] {
        var meta: [String] = []
        meta.append(formatDate(meeting.startTime))
        if let duration = meeting.duration, duration > 0 {
            meta.append(formatDuration(duration))
        }
        if !transcriptSegments.isEmpty {
            let wordCount = transcriptSegments.reduce(0) { $0 + $1.text.split(separator: " ").count }
            if wordCount > 0 {
                let formatted = wordCount >= 1000
                    ? String(format: "%,d words", wordCount).replacingOccurrences(of: ",", with: ",")
                    : "\(wordCount) words"
                meta.append(formatted)
            }
        }
        return meta
    }

    // MARK: - Transcript Tab (design: grid 80px 1fr, gap 14, 1px dividers)

    private var transcriptTabContent: some View {
        Group {
            if transcriptSegments.isEmpty {
                VStack(spacing: 8) {
                    Text("No transcript yet")
                        .font(MonoFont.sans(size: TypeScale.md))
                        .foregroundStyle(MonoColors.textMuted)
                    if !isActivelyScribing {
                        Text("Start scribing to capture transcript")
                            .font(MonoFont.sans(size: TypeScale.sm))
                            .foregroundStyle(MonoColors.textFaint)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Speaker timeline
                    if Set(transcriptSegments.compactMap(\.speakerIndex)).count > 1 {
                        SpeakerTimelineView(segments: transcriptSegments, displayName: displayName(for:))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(MonoColors.bgSubtle)
                        Rectangle().fill(MonoColors.divider).frame(height: 1)
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(groupedTranscript) { seg in
                                    transcriptRow(seg)
                                        .id(seg.id)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                        }
                        .onChange(of: transcriptSegments.count) { _ in
                            if let last = transcriptSegments.last {
                                withAnimation(Anim.standard) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Design: grid [80px | 1fr], gap:14, padding:8px 0, borderBottom 1px divider
    private func transcriptRow(_ seg: TranscriptSegment) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Left column: time + speaker name
            VStack(alignment: .leading, spacing: 1) {
                Text(formatTime(seg.startTime))
                    .font(MonoFont.mono(size: TypeScale.xs))
                    .foregroundStyle(MonoColors.textFaint)
                Text(displayName(for: seg).lowercased())
                    .font(MonoFont.mono(size: 10.5, weight: .semibold))
                    .foregroundStyle(MonoColors.text)
            }
            .frame(width: 80, alignment: .leading)

            // Right column: transcript text
            Text(seg.text)
                .font(MonoFont.sans(size: 12.5))
                .lineSpacing(4)
                .foregroundStyle(MonoColors.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MonoColors.divider).frame(height: 1)
        }
    }

    // MARK: - Notes Tab

    private var notesTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if noteContent.isEmpty && !isActivelyScribing {
                    Text("Write your notes here...")
                        .font(MonoFont.sans(size: TypeScale.md))
                        .foregroundStyle(MonoColors.textFaint)
                        .padding(.horizontal, Spacing.generous)
                        .padding(.top, Spacing.generous)
                }
                TextEditor(text: $noteContent)
                    .font(MonoFont.sans(size: TypeScale.md))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, minHeight: 400)
                    .padding(.horizontal, Spacing.spacious)
                    .padding(.vertical, Spacing.comfortable)
            }
        }
        .onChange(of: noteContent) { _ in debounceSaveNotes() }
    }

    // MARK: - Summary Tab

    private var summaryTabContent: some View {
        Group {
            if isSummarizing {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView().controlSize(.large)
                    Text("Summarizing…")
                        .font(MonoFont.sans(size: TypeScale.lg, weight: .medium))
                        .foregroundStyle(MonoColors.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if isComplete && !summaries.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(summaries) { summary in
                            if let tmpl = SummaryTemplate.all.first(where: { $0.id == summary.summaryType }) {
                                MonoTag("∗ \(tmpl.name.lowercased())", color: MonoColors.accentText, bg: MonoColors.accentBg)
                            }
                            structuredSummary(summary.content)
                        }

                        if !noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Rectangle().fill(MonoColors.divider).frame(height: 1)
                            MonoSectionLabel("YOUR NOTES")
                            Text(renderMarkdown(noteContent))
                                .font(MonoFont.sans(size: TypeScale.md))
                                .textSelection(.enabled)
                                .lineSpacing(4)
                                .foregroundStyle(MonoColors.textMuted)
                        }

                        // Footer actions
                        HStack(spacing: 8) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(summaryAsPlainText(), forType: .string)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                                    Text("copy").font(MonoFont.mono(size: TypeScale.xs, weight: .medium))
                                }
                                .foregroundStyle(MonoColors.textMuted)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.sm))
                                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(MonoColors.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    Spacer().frame(height: 60)
                }
            } else {
                VStack(spacing: 12) {
                    Text("No summary yet")
                        .font(MonoFont.sans(size: TypeScale.md))
                        .foregroundStyle(MonoColors.textMuted)
                    if meeting?.state == "ended" {
                        Text("Click 'generate' to create an AI summary")
                            .font(MonoFont.sans(size: TypeScale.sm))
                            .foregroundStyle(MonoColors.textFaint)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Structured Summary Rendering

    private func parseSummaryIntoSections(_ content: String) -> [(heading: String, body: String)] {
        var sections: [(heading: String, body: String)] = []
        var currentHeading: String?
        var currentBody: [String] = []

        for line in content.components(separatedBy: "\n") {
            if line.range(of: #"^## .+"#, options: .regularExpression) != nil {
                if let heading = currentHeading {
                    sections.append((heading, currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                currentHeading = line.replacingOccurrences(of: "## ", with: "")
                currentBody = []
            } else {
                currentBody.append(line)
            }
        }
        if let heading = currentHeading {
            sections.append((heading, currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
        } else if !currentBody.isEmpty {
            let joined = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { sections.append(("", joined)) }
        }
        return sections
    }

    @ViewBuilder
    private func structuredSummary(_ content: String) -> some View {
        let sections = parseSummaryIntoSections(content)
        if sections.isEmpty {
            Text(renderMarkdown(content))
                .font(MonoFont.sans(size: TypeScale.md))
                .textSelection(.enabled)
                .lineSpacing(5)
        } else {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                summaryBlock(heading: section.heading, body: section.body)
            }
        }
    }

    @ViewBuilder
    private func summaryBlock(heading: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            if !heading.isEmpty {
                HStack(spacing: 8) {
                    MonoSectionLabel(heading)
                    Rectangle().fill(MonoColors.divider).frame(height: 1)
                }
                .padding(.bottom, 2)
            }

            let lines = body.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [x]") }) && !lines.isEmpty {
                actionItemsView(lines)
            } else if lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ✓") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ✔") }) && !lines.isEmpty {
                decisionsView(lines)
            } else if !lines.isEmpty && lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).range(of: #"^\d+[\.\)]\s"#, options: .regularExpression) != nil }) {
                numberedView(lines)
            } else {
                Text(renderMarkdown(body))
                    .font(MonoFont.sans(size: TypeScale.md))
                    .textSelection(.enabled)
                    .lineSpacing(5)
            }
        }
    }

    @ViewBuilder
    private func actionItemsView(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let checked = trimmed.hasPrefix("- [x]")
                let text = trimmed.replacingOccurrences(of: "- [x] ", with: "").replacingOccurrences(of: "- [ ] ", with: "")
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(checked ? MonoColors.accent : MonoColors.textMuted)
                        .frame(width: 16)
                    actionItemText(text)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func actionItemText(_ text: String) -> some View {
        let parts = text.components(separatedBy: " ")
        let attributed = parts.enumerated().reduce(Text("")) { result, item in
            let sep = item.offset == 0 ? Text("") : Text(" ")
            if item.element.hasPrefix("@") {
                return result + sep + Text(item.element).foregroundColor(MonoColors.accent).fontWeight(.medium)
            }
            return result + sep + Text(item.element)
        }
        attributed.font(MonoFont.sans(size: TypeScale.md)).textSelection(.enabled)
    }

    @ViewBuilder
    private func decisionsView(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let text = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "- ✓ ", with: "")
                    .replacingOccurrences(of: "- ✔ ", with: "")
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MonoColors.success)
                    Text(renderMarkdown(text))
                        .font(MonoFont.sans(size: TypeScale.md))
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(MonoColors.border, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private func numberedView(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                let text = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"^\d+[\.\)]\s*"#, with: "", options: .regularExpression)
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d", idx + 1))
                        .font(MonoFont.mono(size: TypeScale.sm))
                        .foregroundStyle(MonoColors.textFaint)
                        .frame(width: 20, alignment: .trailing)
                    Text(renderMarkdown(text))
                        .font(MonoFont.sans(size: TypeScale.md))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                }
                .padding(.vertical, 2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(MonoColors.divider).frame(height: 1)
                }
            }
        }
    }

    // MARK: - Chat Tab (design: grid 60px 1fr, "you ›" / "scribe" labels)

    private var chatTabContent: some View {
        VStack(spacing: 0) {
            // Quick action chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("quick:")
                        .font(MonoFont.mono(size: TypeScale.xs))
                        .foregroundStyle(MonoColors.textFaint)
                    ForEach(["what did i miss?", "action items", "key decisions", "tldr"], id: \.self) { q in
                        Button {
                            sendChat(q)
                        } label: {
                            Text(q)
                                .font(MonoFont.mono(size: 10.5))
                                .foregroundStyle(MonoColors.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.sm))
                                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(MonoColors.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }

            Rectangle().fill(MonoColors.divider).frame(height: 1)

            // Chat messages — design: grid [60px | 1fr]
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(chatMessages) { msg in
                            chatRow(msg)
                                .id(msg.id)
                        }
                        if isChatLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("thinking…")
                                    .font(MonoFont.mono(size: TypeScale.xs))
                                    .foregroundStyle(MonoColors.textMuted)
                            }
                            .padding(.leading, 74)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .onChange(of: chatMessages.count) { _ in
                    if let last = chatMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Design: grid [60px | 1fr], "you ›" right-aligned or "scribe" in accent
    private func chatRow(_ msg: ChatMsg) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(msg.role == .user ? "you ›" : "scribe")
                .font(MonoFont.mono(size: 10.5, weight: .semibold))
                .foregroundStyle(msg.role == .user ? MonoColors.text : MonoColors.accent)
                .frame(width: 60, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                Text(renderMarkdown(msg.text))
                    .font(MonoFont.sans(size: 13.5))
                    .lineSpacing(4)
                    .foregroundStyle(MonoColors.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Citation chips for assistant messages
                if msg.role == .assistant, let sources = msg.sources, !sources.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Text("sources:")
                                .font(MonoFont.mono(size: TypeScale.xs))
                                .foregroundStyle(MonoColors.textFaint)
                            ForEach(sources) { citation in
                                HStack(spacing: 3) {
                                    Text("↗")
                                    Text("\(citation.speaker) \(citation.time)")
                                }
                                .font(MonoFont.mono(size: TypeScale.xs))
                                .foregroundStyle(MonoColors.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.sm))
                                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(MonoColors.border, lineWidth: 1))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Command Bar (design: borderTop divider, bgSubtle, › prompt)

    private var commandBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(MonoColors.divider).frame(height: 1)
            HStack(spacing: 8) {
                Text("›")
                    .font(MonoFont.mono(size: TypeScale.base, weight: .bold))
                    .foregroundStyle(MonoColors.accent)

                TextField("ask · what did i miss?", text: $chatInput)
                    .textFieldStyle(.plain)
                    .font(MonoFont.mono(size: 11.5))
                    .foregroundStyle(MonoColors.text)
                    .onSubmit {
                        let q = chatInput.trimmingCharacters(in: .whitespaces)
                        guard !q.isEmpty else { return }
                        chatInput = ""
                        selectedTab = .chat
                        sendChat(q)
                    }

                if isChatLoading {
                    ProgressView().controlSize(.small)
                }

                // Copy menu
                Menu {
                    Button { copyTranscript() } label: {
                        Label("Copy Transcript", systemImage: "text.quote")
                    }
                    .disabled(transcriptSegments.isEmpty)
                    Button { copySummary() } label: {
                        Label("Copy Summary", systemImage: "doc.plaintext")
                    }
                    .disabled(summaries.isEmpty)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(MonoColors.textFaint)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            // Model/context footer
            HStack(spacing: 0) {
                Text("model: \(AppSettings.shared.llmProvider.rawValue)")
                Text(" · scope: this meeting")
                Text(" · context: \(transcriptWordCount) words")
            }
            .font(MonoFont.mono(size: TypeScale.xs))
            .foregroundStyle(MonoColors.textFaint)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .background(MonoColors.bgSubtle)
    }

    private var transcriptWordCount: Int {
        transcriptSegments.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    // MARK: - Summary Template Picker

    private var summaryTypePicker: some View {
        TemplatePickerView(selectedTemplate: $selectedTemplate) {
            showSummaryPicker = false
            generateWithTemplate()
        }
    }

    private func generateWithTemplate() {
        let tmpl = selectedTemplate
        Task {
            isSummarizing = true
            selectedTab = .summary
            try? await SummarizationService.shared.summarizeMeeting(meetingId: meetingId, template: tmpl)
            try? await MeetingStore.shared.completeMeeting(id: meetingId)
            await loadAll()
            isSummarizing = false
        }
    }

    // MARK: - Markdown

    private func renderMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    // MARK: - Data

    private func loadAll() async {
        meeting = try? await MeetingStore.shared.getMeeting(id: meetingId)
        if let m = meeting { editedTitle = m.title }
        summaries = (try? await MeetingStore.shared.getSummaries(meetingId: meetingId)) ?? []
        detailFolders = (try? await MeetingStore.shared.getFolders()) ?? []
        await loadNotes()
        await loadTranscript()
    }

    private func loadNotes() async {
        let notes = (try? await MeetingStore.shared.getNotes(meetingId: meetingId)) ?? []
        if !notes.isEmpty {
            await MainActor.run {
                if noteContent.isEmpty {
                    noteContent = notes.map(\.text).joined(separator: "\n\n")
                }
            }
        }
    }

    private func debounceSaveNotes() {
        let content = noteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        Task {
            let existing = (try? await MeetingStore.shared.getNotes(meetingId: meetingId)) ?? []
            if let first = existing.first {
                var updated = first; updated.text = content
                try? await MeetingStore.shared.updateNote(updated)
            } else {
                let note = UserNote(meetingId: meetingId, text: content, timestamp: Date().timeIntervalSinceReferenceDate)
                try? await MeetingStore.shared.addNote(note)
            }
        }
    }

    private func loadTranscript() async {
        transcriptSegments = (try? await MeetingStore.shared.getTranscript(meetingId: meetingId)) ?? []
    }

    private func startPollingIfNeeded() {
        guard isActivelyScribing else { return }
        transcriptPollTask = Task {
            while !Task.isCancelled {
                await loadTranscript()
                meeting = try? await MeetingStore.shared.getMeeting(id: meetingId)
                if !isActivelyScribing { break }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func saveTitle() {
        guard !editedTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            if var m = try? await MeetingStore.shared.getMeeting(id: meetingId) {
                m.title = editedTitle.trimmingCharacters(in: .whitespaces)
                try? await MeetingStore.shared.updateMeeting(m)
                await loadAll()
                NotificationCenter.default.post(name: .meetingUpdated, object: nil)
            }
        }
    }

    private func sendChat(_ question: String? = nil) {
        let q = question ?? chatInput.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if question == nil { chatInput = "" }
        if selectedTab != .chat {
            withAnimation(Anim.fast) { selectedTab = .chat }
        }

        withAnimation(Anim.panel) {
            chatMessages.append(ChatMsg(role: .user, text: q))
        }
        isChatLoading = true

        Task {
            await chatService.start(meetingId: meetingId)
            do {
                let response = try await chatService.ask(q)
                await MainActor.run {
                    withAnimation(Anim.panel) {
                        chatMessages.append(ChatMsg(role: .assistant, text: response))
                    }
                    isChatLoading = false
                }
            } catch {
                await MainActor.run {
                    withAnimation(Anim.panel) {
                        chatMessages.append(ChatMsg(role: .assistant, text: "Error: \(error.localizedDescription)"))
                    }
                    isChatLoading = false
                }
            }
        }
    }

    // MARK: - Copy Helpers

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptAsPlainText(), forType: .string)
    }

    private func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summaryAsPlainText(), forType: .string)
    }

    private func transcriptAsPlainText() -> String {
        transcriptSegments.map { seg in
            "[\(formatTime(seg.startTime))] \(displayName(for: seg)): \(seg.text)"
        }.joined(separator: "\n")
    }

    private func summaryAsPlainText() -> String {
        summaries.map { summary in
            if summary.summaryType == "full" { return summary.content }
            let heading = summary.summaryType.replacingOccurrences(of: "_", with: " ").capitalized
            return "\(heading)\n\(summary.content)"
        }.joined(separator: "\n\n")
    }

    // MARK: - Speaker

    private func displayName(for segment: TranscriptSegment) -> String {
        guard let idx = segment.speakerIndex else {
            return segment.speaker ?? "Unknown"
        }
        if idx == 0 { return "You" }
        if let meeting, let participantsJSON = meeting.participants,
           let data = participantsJSON.data(using: .utf8),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            let participantIdx = idx - 1
            if participantIdx >= 0 && participantIdx < names.count {
                return names[participantIdx]
            }
        }
        return "Speaker \(idx)"
    }

    private func formatDate(_ d: Date) -> String { ScribeDateFormatting.shortDate(d) }
    private func formatDuration(_ s: TimeInterval) -> String { ScribeDateFormatting.duration(s) }
    private func formatTime(_ s: TimeInterval) -> String { ScribeDateFormatting.transcriptTime(s) }
}

private struct ChatCitation: Identifiable {
    let id = UUID()
    let speaker: String
    let time: String
    let segmentId: UUID?
}

private struct ChatMsg: Identifiable {
    let id = UUID(); let role: Role; let text: String
    var sources: [ChatCitation]?
    enum Role { case user, assistant }
}

// MARK: - Template Picker

private struct TemplatePickerView: View {
    @Binding var selectedTemplate: SummaryTemplate
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meeting Type")
                .font(MonoFont.sans(size: TypeScale.md, weight: .semibold))

            ForEach(SummaryTemplate.all) { tmpl in
                templateRow(tmpl)
            }

            Rectangle().fill(MonoColors.divider).frame(height: 1)

            sectionsPreview

            Button(action: onGenerate) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Generate")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(MonoPrimaryButtonStyle())
        }
        .padding(12)
        .frame(width: 240)
    }

    private func templateRow(_ tmpl: SummaryTemplate) -> some View {
        let isSelected = selectedTemplate.id == tmpl.id
        return HStack(spacing: 8) {
            Image(systemName: tmpl.icon)
                .frame(width: 16)
                .foregroundStyle(isSelected ? MonoColors.accent : MonoColors.textMuted)
            VStack(alignment: .leading, spacing: 1) {
                Text(tmpl.name)
                    .font(MonoFont.sans(size: TypeScale.sm))
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(tmpl.description)
                    .font(MonoFont.sans(size: TypeScale.xs))
                    .foregroundStyle(MonoColors.textFaint)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundStyle(MonoColors.accent)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? MonoColors.accentBg : Color.clear,
                    in: RoundedRectangle(cornerRadius: Radius.md))
        .contentShape(Rectangle())
        .onTapGesture { selectedTemplate = tmpl }
    }

    private var sectionsPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sections:")
                .font(MonoFont.mono(size: TypeScale.xs))
                .foregroundStyle(MonoColors.textFaint)
            ForEach(selectedTemplate.sections) { section in
                Text("• \(section.heading)")
                    .font(MonoFont.sans(size: TypeScale.xs))
                    .foregroundStyle(MonoColors.textMuted)
            }
        }
    }
}

// MARK: - Speaker Timeline

private struct SpeakerTimelineView: View {
    let segments: [TranscriptSegment]
    let displayName: (TranscriptSegment) -> String

    private var speakerData: [(index: Int, name: String, ranges: [(start: TimeInterval, end: TimeInterval)])] {
        guard !segments.isEmpty else { return [] }
        var byIndex: [Int: (name: String, ranges: [(start: TimeInterval, end: TimeInterval)])] = [:]
        for seg in segments {
            let idx = seg.speakerIndex ?? -1
            if byIndex[idx] == nil {
                byIndex[idx] = (name: displayName(seg), ranges: [])
            }
            byIndex[idx]?.ranges.append((start: seg.startTime, end: seg.endTime))
        }
        return byIndex.keys.sorted().map { idx in
            let data = byIndex[idx]!
            return (index: idx, name: data.name, ranges: data.ranges)
        }
    }

    private var totalDuration: TimeInterval {
        guard let first = segments.first, let last = segments.last else { return 1 }
        return max(last.endTime - first.startTime, 1)
    }

    private var timelineStart: TimeInterval { segments.first?.startTime ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                MonoSectionLabel("SPEAKER TIMELINE")
                Rectangle().fill(MonoColors.divider).frame(height: 1)
            }
            .padding(.bottom, 4)

            ForEach(speakerData, id: \.index) { speaker in
                HStack(spacing: 8) {
                    Text(speaker.name.lowercased())
                        .font(MonoFont.mono(size: TypeScale.xs))
                        .foregroundStyle(speaker.index == 0 ? MonoColors.text : MonoColors.textMuted)
                        .fontWeight(speaker.index == 0 ? .semibold : .regular)
                        .frame(width: 70, alignment: .trailing)
                        .lineLimit(1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(MonoColors.bgSubtle)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(MonoColors.divider, lineWidth: 1))

                            ForEach(Array(speaker.ranges.enumerated()), id: \.offset) { _, range in
                                let startFrac = (range.start - timelineStart) / totalDuration
                                let widthFrac = (range.end - range.start) / totalDuration
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(SpeakerColors.color(for: speaker.index))
                                    .opacity(speaker.index == 0 ? 0.85 : 0.6)
                                    .frame(width: max(widthFrac * geo.size.width, 2))
                                    .offset(x: startFrac * geo.size.width)
                            }
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }
}
