import SwiftUI
import ScribeCore

/// Timestamped note input during meetings
public struct NoteInputView: View {
    let meetingId: UUID
    @State private var noteText = ""
    @State private var notes: [UserNote] = []
    @FocusState private var isInputFocused: Bool

    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Notes list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(notes) { note in
                        NoteRow(note: note)
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
        .task {
            await loadNotes()
        }
    }

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
            try? await MeetingStore.shared.addNote(note)
            await loadNotes()
        }
    }

    private func loadNotes() async {
        if let fetched = try? await MeetingStore.shared.getNotes(meetingId: meetingId) {
            await MainActor.run {
                notes = fetched
            }
        }
    }
}

struct NoteRow: View {
    let note: UserNote

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.text)
                .font(.caption)
                .textSelection(.enabled)
            Text(formatTimestamp(note.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private func formatTimestamp(_ ts: TimeInterval) -> String {
        let date = Date(timeIntervalSinceReferenceDate: ts)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
