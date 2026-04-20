import SwiftUI
import ScribeCore

/// Timestamped note input during meetings with edit/delete and templates
public struct NoteInputView: View {
    let meetingId: UUID
    @State private var noteText = ""
    @State private var notes: [UserNote] = []
    @State private var editingNoteId: UUID?
    @State private var editText = ""
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Templates
            noteTemplates

            Divider()

            // Notes list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(notes) { note in
                        if editingNoteId == note.id {
                            editRow(note: note)
                        } else {
                            NoteRow(
                                note: note,
                                onEdit: { startEditing(note) },
                                onDelete: { deleteNote(note) }
                            )
                            .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            // Input area
            HStack(spacing: 8) {
                TextField("Add a note...", text: $noteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .lineLimit(1...3)
                    .focused($isInputFocused)
                    .onSubmit {
                        addNote()
                    }

                Button {
                    addNote()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .errorBanner($errorMessage)
        .task {
            await loadNotes()
        }
    }

    // MARK: - Templates

    private var noteTemplates: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                templateChip("Action Item", "- [ ] **What:** \n- **Who:** \n- **By:**")
                templateChip("Decision", "**Decision:** \n**Context:** \n**Owner:**")
                templateChip("Question", "**Q:** \n**A:**")
                templateChip("Follow-up", "**Follow-up:** \n**Owner:** \n**By:**")
                templateChip("1:1 Notes", "## Updates\n- \n\n## Blockers\n- \n\n## Action Items\n- [ ] ")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func templateChip(_ title: String, _ content: String) -> some View {
        Button {
            noteText = content
            isInputFocused = true
        } label: {
            Text(title)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(ScribeButtonStyle())
    }

    // MARK: - Edit Row

    private func editRow(note: UserNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Edit note...", text: $editText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.caption)
                .lineLimit(1...5)

            HStack(spacing: 8) {
                Button("Save") { saveEdit(note) }
                    .font(.caption2).buttonStyle(.borderedProminent).controlSize(.mini)
                Button("Cancel") { editingNoteId = nil }
                    .font(.caption2).buttonStyle(.bordered).controlSize(.mini)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    private func addNote() {
        let text = noteText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let note = UserNote(
            meetingId: meetingId,
            text: text,
            timestamp: Date().timeIntervalSinceReferenceDate
        )

        noteText = ""

        Task {
            do {
                try await MeetingStore.shared.addNote(note)
                await loadNotes()
            } catch {
                errorMessage = "Failed to save note"
            }
        }
    }

    private func startEditing(_ note: UserNote) {
        editingNoteId = note.id
        editText = note.text
    }

    private func saveEdit(_ note: UserNote) {
        let text = editText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        var updated = note
        updated.text = text

        Task {
            do {
                try await MeetingStore.shared.updateNote(updated)
                editingNoteId = nil
                await loadNotes()
            } catch {
                errorMessage = "Failed to update note"
            }
        }
    }

    private func deleteNote(_ note: UserNote) {
        Task {
            do {
                try await MeetingStore.shared.deleteNote(id: note.id)
                withAnimation(Anim.standard) {
                    notes.removeAll { $0.id == note.id }
                }
            } catch {
                errorMessage = "Failed to delete note"
            }
        }
    }

    private func loadNotes() async {
        do {
            let fetched = try await MeetingStore.shared.getNotes(meetingId: meetingId)
            await MainActor.run { notes = fetched }
        } catch {
            errorMessage = "Failed to load notes"
        }
    }
}

struct NoteRow: View {
    let note: UserNote
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.text)
                    .font(.caption)
                    .textSelection(.enabled)
                Text(formatTimestamp(note.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isHovered {
                HStack(spacing: 4) {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit note")

                    Button { onDelete() } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Delete note")
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
        .animation(Anim.fast, value: isHovered)
    }

    private func formatTimestamp(_ ts: TimeInterval) -> String {
        let date = Date(timeIntervalSinceReferenceDate: ts)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
