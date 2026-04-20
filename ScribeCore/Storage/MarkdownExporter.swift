import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "MarkdownExporter")

/// Exports completed meetings as human-readable markdown files to the user-configured folder
public actor MarkdownExporter {
    public static let shared = MarkdownExporter()
    private init() {}

    /// Resolved export directory from settings
    private func exportDir() async -> URL {
        let url = await AppSettings.shared.meetingStorageURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Export a meeting as a markdown file. Called after meeting completion.
    public func exportMeeting(id: UUID) async throws {
        let store = MeetingStore.shared

        guard let meeting = try await store.getMeeting(id: id) else { return }

        let transcript = try await store.getTranscript(meetingId: id)
        let notes = try await store.getNotes(meetingId: id)
        let summaries = try await store.getSummaries(meetingId: id)

        let md = buildMarkdown(meeting: meeting, transcript: transcript, notes: notes, summaries: summaries)

        let dir = await exportDir()
        let filename = buildFilename(meeting: meeting)
        let fileURL = dir.appendingPathComponent(filename)

        try md.write(to: fileURL, atomically: true, encoding: .utf8)
        logger.info("Exported meeting to \(fileURL.path)")
    }

    // MARK: - Build Markdown

    private func buildMarkdown(meeting: MeetingRecord, transcript: [TranscriptSegment], notes: [UserNote], summaries: [AISummary]) -> String {
        var md = ""

        // YAML frontmatter
        let dateFormatter = ISO8601DateFormatter()
        let durationStr: String
        if let d = meeting.duration {
            let mins = Int(d) / 60
            durationStr = mins < 60 ? "\(mins)m" : "\(mins / 60)h \(mins % 60)m"
        } else {
            durationStr = "unknown"
        }

        md += "---\n"
        md += "id: \(meeting.id.uuidString)\n"
        md += "title: \"\(meeting.title.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
        md += "date: \(dateFormatter.string(from: meeting.startTime))\n"
        md += "duration: \(durationStr)\n"
        if let participants = meeting.participants {
            md += "participants: \(participants)\n"
        }
        md += "state: \(meeting.state)\n"
        md += "---\n\n"

        md += "# \(meeting.title)\n\n"

        // Summaries
        for summary in summaries {
            md += summary.content.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        }

        // User notes
        if !notes.isEmpty {
            md += "## Notes\n\n"
            for note in notes {
                let time = formatTime(note.timestamp)
                md += "- **[\(time)]** \(note.text)\n"
            }
            md += "\n"
        }

        // Transcript
        if !transcript.isEmpty {
            md += "## Transcript\n\n"
            for seg in transcript {
                let speaker = seg.speaker ?? "Unknown"
                md += "**\(speaker):** \(seg.text)\n\n"
            }
        }

        return md
    }

    private func buildFilename(meeting: MeetingRecord) -> String {
        let safeTitle = meeting.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .prefix(60)
        let datePart = formatDateForFilename(meeting.startTime)
        return "\(datePart)-\(safeTitle).md"
    }

    private func formatTime(_ ts: TimeInterval) -> String {
        let date = Date(timeIntervalSinceReferenceDate: ts)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
