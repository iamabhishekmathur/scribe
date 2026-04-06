import SwiftUI
import ScribeCore

/// Meeting detail: Notes editor during scribing, processed summary after.
/// Bottom bar with chat input + transcript toggle.
public struct MeetingDetailView: View {
    let meetingId: UUID
    @State private var meeting: MeetingRecord?
    @State private var isEditingTitle = false
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
                        if isSummarizing {
                            summarizingView
                        } else if isComplete && !summaries.isEmpty {
                            processedSummaryView
                        } else {
                            notesEditor
                        }
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
            if isEditingTitle {
                HStack {
                    TextField("Meeting title", text: $editedTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .onSubmit { saveTitle() }
                    Button("Save") { saveTitle() }.controlSize(.small)
                    Button("Cancel") { editedTitle = meeting.title; isEditingTitle = false }.controlSize(.small)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(meeting.title)
                        .font(.system(.title2, design: .serif))
                        .fontWeight(.bold)
                    Button { isEditingTitle = true } label: {
                        Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit meeting title")
                }
            }

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

                Menu {
                    Button("Export as JSON") {
                        Task {
                            if let url = try? await JSONExporter.shared.exportMeeting(id: meetingId) {
                                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                            }
                        }
                    }
                    if !detailFolders.isEmpty {
                        Menu("Move to Folder") {
                            ForEach(detailFolders) { folder in
                                Button {
                                    Task {
                                        try? await MeetingStore.shared.moveMeetingToFolder(meetingId: meetingId, folderId: folder.id)
                                        NotificationCenter.default.post(name: .meetingUpdated, object: nil)
                                        await loadAll()
                                    }
                                } label: {
                                    HStack {
                                        Text(folder.name)
                                        if meeting.folderId == folder.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            if meeting.folderId != nil {
                                Divider()
                                Button("Remove from Folder") {
                                    Task {
                                        try? await MeetingStore.shared.moveMeetingToFolder(meetingId: meetingId, folderId: nil)
                                        NotificationCenter.default.post(name: .meetingUpdated, object: nil)
                                        await loadAll()
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Delete Meeting", role: .destructive) {
                        Task {
                            try? await MeetingStore.shared.deleteMeeting(id: meetingId)
                            NotificationCenter.default.post(name: .meetingDeleted, object: meetingId)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.body)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Meeting options")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                }

                TextEditor(text: $noteContent)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, minHeight: 400)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
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
            .padding(24)
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

    // MARK: - Transcript Panel

    private var transcriptPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcript")
                    .font(.callout).fontWeight(.semibold)
                Spacer()
                Text("\(transcriptSegments.count) segments")
                    .font(.caption).foregroundStyle(.tertiary)
                Button { withAnimation(.spring(duration: 0.3)) { showTranscript = false } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close transcript")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

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
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(transcriptSegments) { seg in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(formatTime(seg.startTime))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 36, alignment: .trailing)
                                    if let speaker = seg.speaker {
                                        Text(speaker)
                                            .font(.caption2).fontWeight(.semibold)
                                            .foregroundStyle(.blue)
                                    }
                                    Text(seg.text)
                                        .font(.system(.callout, design: .serif))
                                        .textSelection(.enabled)
                                }
                                .id(seg.id)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                    .onChange(of: transcriptSegments.count) { _ in
                        if let last = transcriptSegments.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(height: 250)
        .background(.ultraThinMaterial)
        .transition(.move(edge: .bottom))
    }

    // MARK: - Bottom Bar (Granola-style split waveform)

    private var chatBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                // Left pill: [waveform dots + chevron] | [stop]
                HStack(spacing: 0) {
                    // Left half — show/hide transcript
                    Button {
                        withAnimation(.spring(duration: 0.3)) { showTranscript.toggle() }
                        if showTranscript { Task { await loadTranscript() } }
                    } label: {
                        HStack(spacing: 5) {
                            // Animated waveform dots
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(isActivelyScribing ? .green : .secondary.opacity(0.4))
                                        .frame(width: 3, height: isActivelyScribing ? [6, 10, 7][i] : 4)
                                }
                            }
                            Image(systemName: showTranscript ? "chevron.down" : "chevron.up")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .help(showTranscript ? "Hide transcript" : "Show transcript")

                    // Divider line between left and right
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1, height: 20)

                    // Right half — stop scribing
                    Button {
                        if isActivelyScribing {
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
                        } else {
                            // Start scribing
                            Task {
                                await coordinator.startRecording(meetingId: meetingId, title: meeting?.title ?? "Meeting")
                            }
                        }
                    } label: {
                        Image(systemName: isActivelyScribing ? "stop.fill" : "circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(isActivelyScribing ? .secondary : .green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .help(isActivelyScribing ? "Stop scribing" : "Start scribing")
                }
                .background(.quaternary.opacity(0.5), in: Capsule())

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
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.3), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
        isEditingTitle = false
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
        if !showChat { withAnimation { showChat = true } }

        chatMessages.append(ChatMsg(role: .user, text: q))
        isChatLoading = true

        Task {
            // Initialize chat service for this meeting if needed
            await chatService.start(meetingId: meetingId)

            do {
                let response = try await chatService.ask(q)
                await MainActor.run {
                    chatMessages.append(ChatMsg(role: .assistant, text: response))
                    isChatLoading = false
                }
            } catch {
                await MainActor.run {
                    chatMessages.append(ChatMsg(role: .assistant, text: "Error: \(error.localizedDescription)"))
                    isChatLoading = false
                }
            }
        }
    }

    private func formatDate(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d) }
    private func formatDuration(_ s: TimeInterval) -> String {
        let m = Int(s) / 60; if m < 1 { return "\(Int(s))s" }; if m < 60 { return "\(m) min" }; return "\(m/60)h \(m%60)m"
    }
    private func formatTime(_ s: TimeInterval) -> String { String(format: "%d:%02d", Int(s)/60, Int(s)%60) }
}

private struct ChatMsg: Identifiable {
    let id = UUID(); let role: Role; let text: String
    enum Role { case user, assistant }
}
