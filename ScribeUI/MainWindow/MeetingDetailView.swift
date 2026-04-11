import SwiftUI
import ScribeCore

/// Meeting detail: Notes editor during scribing, processed summary after.
/// Bottom bar with chat input + transcript toggle.
public struct MeetingDetailView: View {
    let meetingId: UUID
    @State private var meeting: MeetingRecord?
    @State private var editedTitle = ""
    @State private var showTranscript = false
    @State private var noteContent = ""
    @State private var chatInput = ""
    @State private var chatMessages: [ChatMsg] = []
    @State private var isChatLoading = false
    @State private var showChat = false
    @State private var isSummarizing = false
    @State private var chatService = ChatService()
    @State private var transcriptSegments: [TranscriptSegment] = []
    @State private var summaries: [AISummary] = []
    @State private var transcriptPollTask: Task<Void, Never>?
    @State private var detailFolders: [Folder] = []
    @State private var transcriptHeight: CGFloat = 250
    @FocusState private var titleFieldFocused: Bool

    @ObservedObject private var coordinator = RecordingCoordinator.shared

    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }

    private var isActivelyScribing: Bool {
        coordinator.isRecording && coordinator.currentMeetingId == meetingId
    }

    private var isComplete: Bool {
        meeting?.state == "complete"
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let meeting {
                meetingHeader(meeting)
                Divider()

                // Main content
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Group {
                            if isSummarizing {
                                summarizingView
                                    .transition(.opacity)
                            } else if isComplete && !summaries.isEmpty {
                                processedSummaryView
                                    .transition(.opacity)
                            } else {
                                notesEditor
                                    .transition(.opacity)
                            }
                        }
                        .animation(Anim.standard, value: isSummarizing)
                        .animation(Anim.standard, value: isComplete)
                        Spacer()
                    }

                    VStack(spacing: 0) {
                        if showChat { chatPanel }
                        if showTranscript { transcriptPanel }
                        chatBar
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loadAll(); startPollingIfNeeded() }
        .onChange(of: meetingId) { _ in
            transcriptPollTask?.cancel()
            Task { await loadAll(); startPollingIfNeeded() }
        }
        .onDisappear { transcriptPollTask?.cancel() }
    }

    // MARK: - Header

    private func meetingHeader(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Meeting title", text: $editedTitle)
                .textFieldStyle(.plain)
                .font(.system(.title2, design: .serif).weight(.bold))
                .focused($titleFieldFocused)
                .onSubmit { saveTitle() }
                .onChange(of: titleFieldFocused) { focused in
                    if !focused { saveTitle() }
                }
                .onHover { hovering in
                    if hovering {
                        NSCursor.iBeam.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .accessibilityLabel("Meeting title, click to edit")

            HStack(spacing: 8) {
                Label(formatDate(meeting.startTime), systemImage: "calendar")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5), in: Capsule())

                if let duration = meeting.duration, duration > 0 {
                    Label(formatDuration(duration), systemImage: "clock")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }

                if isActivelyScribing {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("Scribing")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.green.opacity(0.12), in: Capsule())
                    .foregroundStyle(.green)
                }

                Spacer()

                Button {
                    Task {
                        try? await MeetingStore.shared.deleteMeeting(id: meetingId)
                        NotificationCenter.default.post(name: .meetingDeleted, object: meetingId)
                    }
                } label: {
                    Image(systemName: "trash").font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete meeting")
                .accessibilityLabel("Delete meeting")
            }
        }
        .padding(.horizontal, Spacing.spacious)
        .padding(.vertical, Spacing.standard)
    }

    // MARK: - Summarizing Loading State

    private var summarizingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Summarizing your meeting...")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Scribe is analyzing the transcript and your notes")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Notes Editor (during scribing or pre-complete)

    private var notesEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if noteContent.isEmpty && !isActivelyScribing {
                    Text("Write your notes here...")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, Spacing.generous)
                        .padding(.top, Spacing.generous)
                }

                TextEditor(text: $noteContent)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, minHeight: 400)
                    .padding(.horizontal, Spacing.spacious)
                    .padding(.vertical, Spacing.comfortable)
            }
        }
        .onChange(of: noteContent) { _ in debounceSaveNotes() }
    }

    // MARK: - Processed Summary (after scribing complete)

    private var processedSummaryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(summaries) { summary in
                    VStack(alignment: .leading, spacing: 8) {
                        if summary.summaryType != "full" {
                            Text(summary.summaryType.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(.title3, design: .serif))
                                .fontWeight(.semibold)
                        }
                        Text(renderMarkdown(summary.content))
                            .font(.system(.body, design: .serif))
                            .textSelection(.enabled)
                            .lineSpacing(5)
                    }
                    if summary.id != summaries.last?.id { Divider() }
                }

                if !noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider()
                    Text("Your Notes")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(.secondary)
                    Text(renderMarkdown(noteContent))
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.generous)
            Spacer().frame(height: 80)
        }
    }

    private func renderMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat with Scribe")
                    .font(.callout).fontWeight(.semibold)
                Spacer()
                Button { withAnimation { showChat = false } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close chat")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chatMessages) { msg in
                            HStack {
                                if msg.role == .user { Spacer(minLength: 60) }
                                Text(renderMarkdown(msg.text))
                                    .font(.system(.callout, design: .serif))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        msg.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .textSelection(.enabled)
                                if msg.role == .assistant { Spacer(minLength: 60) }
                            }
                            .id(msg.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                        if isChatLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Thinking...").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                }
                .onChange(of: chatMessages.count) { _ in
                    if let last = chatMessages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .frame(height: 250)
        .background(.ultraThinMaterial)
        .transition(.move(edge: .bottom))
    }

    // MARK: - Transcript Panel (resizable)

    private var transcriptPanel: some View {
        VStack(spacing: 0) {
            // Drag handle for resizing
            transcriptDragHandle

            HStack {
                Text("Transcript")
                    .font(.callout).fontWeight(.semibold)
                Spacer()
                Text("\(transcriptSegments.count) segments")
                    .font(.caption).foregroundStyle(.tertiary)
                Button { withAnimation(Anim.panel) { showTranscript = false } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close transcript")
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            Divider()

            if transcriptSegments.isEmpty {
                VStack(spacing: 8) {
                    Text("No transcript yet")
                        .font(.callout).foregroundStyle(.secondary)
                    if !isActivelyScribing {
                        Text("Start scribing to capture transcript")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(transcriptSegments) { seg in
                                transcriptBubble(seg)
                                    .id(seg.id)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .onChange(of: transcriptSegments.count) { _ in
                        if let last = transcriptSegments.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(height: transcriptHeight)
        .background(.ultraThinMaterial)
        .transition(.move(edge: .bottom))
    }

    /// Draggable resize handle at the top of the transcript panel
    private var transcriptDragHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                    .frame(width: 36, height: 4)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Dragging up (negative translation) = bigger panel
                        let newHeight = transcriptHeight - value.translation.height
                        transcriptHeight = min(max(newHeight, 120), 600)
                    }
            )
    }

    // MARK: - Bottom Bar

    private var chatBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                // Left pill: [waveform icon | copy icon]
                HStack(spacing: 0) {
                    // Waveform — toggle transcript
                    Button {
                        withAnimation(Anim.panel) { showTranscript.toggle() }
                        if showTranscript { Task { await loadTranscript() } }
                    } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isActivelyScribing ? .green : (showTranscript ? .primary : .secondary))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(ScribeButtonStyle())
                    .help(showTranscript ? "Hide transcript" : "Show transcript")
                    .accessibilityLabel(showTranscript ? "Hide transcript" : "Show transcript")

                    // Divider line
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1, height: 20)

                    // Copy menu
                    Menu {
                        Button {
                            let text = transcriptAsPlainText()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        } label: {
                            Label("Copy Transcript", systemImage: "text.quote")
                        }
                        .disabled(transcriptSegments.isEmpty)

                        Button {
                            let text = summaryAsPlainText()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        } label: {
                            Label("Copy Summary", systemImage: "doc.plaintext")
                        }
                        .disabled(summaries.isEmpty)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 34)
                    .help("Copy transcript or summary")
                    .accessibilityLabel("Copy options")
                }
                .background(.quaternary.opacity(0.5), in: Capsule())

                // Stop button (visible when recording)
                if isActivelyScribing {
                    Button {
                        Task {
                            isSummarizing = true
                            await coordinator.stopRecording()
                            for _ in 0..<30 {
                                try? await Task.sleep(for: .seconds(2))
                                let m = try? await MeetingStore.shared.getMeeting(id: meetingId)
                                if m?.state == "complete" { break }
                            }
                            await loadAll()
                            isSummarizing = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                            Text("Stop")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(ScribeButtonStyle())
                    .background(.red.opacity(0.12), in: Capsule())
                    .help("Stop recording and generate summary")
                    .accessibilityLabel("Stop recording")
                }

                // Generate Summary button (for ended meetings without summary)
                if !isActivelyScribing && meeting?.state == "ended" && summaries.isEmpty {
                    Button {
                        Task {
                            isSummarizing = true
                            try? await SummarizationService.shared.summarizeMeeting(meetingId: meetingId)
                            try? await MeetingStore.shared.completeMeeting(id: meetingId)
                            await loadAll()
                            isSummarizing = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Generate Summary")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(ScribeButtonStyle())
                    .background(.purple.opacity(0.12), in: Capsule())
                    .help("Process transcript and generate summary")
                }

                // Ask anything input
                HStack(spacing: 8) {
                    TextField("Ask anything", text: $chatInput)
                        .textFieldStyle(.plain)
                        .font(.system(.callout, design: .serif))
                        .onSubmit { sendChat() }

                    if isChatLoading {
                        ProgressView().controlSize(.small)
                    }

                    // Chat toggle if messages exist
                    if !chatMessages.isEmpty {
                        Button {
                            withAnimation { showChat.toggle() }
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.caption)
                                .foregroundStyle(showChat ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(showChat ? "Hide chat history" : "Show chat history")
                        .accessibilityLabel(showChat ? "Hide chat history" : "Show chat history")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.3), in: Capsule())
            }
            .padding(.horizontal, Spacing.standard)
            .padding(.vertical, Spacing.compact)
            .background(.bar)
        }
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

    private var saveTimer: Timer? { nil }

    private func debounceSaveNotes() {
        // Simple save on every change (TextEditor fires per keystroke)
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
                // Also reload meeting state
                meeting = try? await MeetingStore.shared.getMeeting(id: meetingId)
                summaries = (try? await MeetingStore.shared.getSummaries(meetingId: meetingId)) ?? []
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

    private func sendChat() {
        let q = chatInput.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        chatInput = ""

        // Open chat panel if not visible
        if !showChat { withAnimation(Anim.panel) { showChat = true } }

        withAnimation(Anim.panel) {
            chatMessages.append(ChatMsg(role: .user, text: q))
        }
        isChatLoading = true

        Task {
            // Initialize chat service for this meeting if needed
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

    // MARK: - Transcript Bubble (iMessage-style)

    @ViewBuilder
    private func transcriptBubble(_ seg: TranscriptSegment) -> some View {
        let isUser = seg.speakerIndex == 0
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if !isUser {
                        Text(displayName(for: seg))
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(speakerColor(for: seg))
                    }
                    Text(formatTime(seg.startTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    if isUser {
                        Text("You")
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(seg.text)
                    .font(.system(.callout, design: .serif))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        isUser ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    // MARK: - Copy Helpers

    private func transcriptAsPlainText() -> String {
        transcriptSegments.map { seg in
            let speaker = displayName(for: seg)
            let time = formatTime(seg.startTime)
            return "[\(time)] \(speaker): \(seg.text)"
        }.joined(separator: "\n")
    }

    private func summaryAsPlainText() -> String {
        summaries.map { summary in
            if summary.summaryType == "full" {
                return summary.content
            }
            let heading = summary.summaryType.replacingOccurrences(of: "_", with: " ").capitalized
            return "\(heading)\n\(summary.content)"
        }.joined(separator: "\n\n")
    }

    // MARK: - Speaker Display Names

    /// Resolve a display name for a transcript segment.
    /// speakerIndex 0 = "You" (mic input), others = participant name from calendar or "Speaker N" (1-based)
    private func displayName(for segment: TranscriptSegment) -> String {
        guard let idx = segment.speakerIndex else {
            return segment.speaker ?? "Unknown"
        }
        // Speaker 0 is the user (mic input)
        if idx == 0 { return "You" }
        // Try to resolve from calendar participants
        if let meeting, let participantsJSON = meeting.participants,
           let data = participantsJSON.data(using: .utf8),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            // idx 1 maps to first participant, idx 2 to second, etc.
            let participantIdx = idx - 1
            if participantIdx >= 0 && participantIdx < names.count {
                return names[participantIdx]
            }
        }
        // Fallback: 1-based numbering
        return "Speaker \(idx)"
    }

    private func speakerColor(for segment: TranscriptSegment) -> Color {
        guard let idx = segment.speakerIndex else { return .primary }
        if idx == 0 { return .accentColor }
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint]
        return colors[(idx - 1) % colors.count]
    }

    private var isUserSegment: (TranscriptSegment) -> Bool {
        { $0.speakerIndex == 0 }
    }

    private func formatDate(_ d: Date) -> String { ScribeDateFormatting.shortDate(d) }
    private func formatDuration(_ s: TimeInterval) -> String { ScribeDateFormatting.duration(s) }
    private func formatTime(_ s: TimeInterval) -> String { ScribeDateFormatting.transcriptTime(s) }
}

private struct ChatMsg: Identifiable {
    let id = UUID(); let role: Role; let text: String
    enum Role { case user, assistant }
}
