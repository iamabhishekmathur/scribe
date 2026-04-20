import Foundation
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "MarkdownImporter")

/// Imports meeting markdown files into SQLite. Used for sync/recovery.
/// Only imports meetings whose UUID doesn't already exist in the database.
public actor MarkdownImporter {
    public static let shared = MarkdownImporter()
    private init() {}

    /// Scan the meeting storage folder and import any meetings not in SQLite
    public func syncFromFolder() async {
        let dir = await AppSettings.shared.meetingStorageURL

        guard FileManager.default.fileExists(atPath: dir.path) else {
            logger.info("Meeting storage folder doesn't exist yet, skipping import")
            return
        }

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "md" }
        } catch {
            logger.error("Failed to list meeting files: \(error.localizedDescription)")
            return
        }

        var imported = 0
        for file in files {
            do {
                if try await importFileIfNeeded(file) {
                    imported += 1
                }
            } catch {
                logger.warning("Failed to import \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if imported > 0 {
            logger.info("Imported \(imported) meeting(s) from markdown")
        }
    }

    /// Import a single file if its meeting ID doesn't exist in SQLite. Returns true if imported.
    private func importFileIfNeeded(_ url: URL) async throws -> Bool {
        let content = try String(contentsOf: url, encoding: .utf8)

        guard let frontmatter = parseFrontmatter(content) else { return false }
        guard let idStr = frontmatter["id"], let meetingId = UUID(uuidString: idStr) else { return false }

        // Skip if already in database
        if let _ = try await MeetingStore.shared.getMeeting(id: meetingId) {
            return false
        }

        let title = frontmatter["title"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? url.deletingPathExtension().lastPathComponent
        let state = frontmatter["state"] ?? "complete"

        let startTime: Date
        if let dateStr = frontmatter["date"] {
            startTime = ISO8601DateFormatter().date(from: dateStr) ?? Date()
        } else {
            startTime = Date()
        }

        let duration: TimeInterval?
        if let durStr = frontmatter["duration"], durStr != "unknown" {
            duration = parseDuration(durStr)
        } else {
            duration = nil
        }

        let participants = frontmatter["participants"]

        // Create meeting record
        var meeting = MeetingRecord(id: meetingId, title: title)
        meeting.startTime = startTime
        meeting.duration = duration
        meeting.endTime = duration.map { startTime.addingTimeInterval($0) }
        meeting.state = state
        meeting.participants = participants
        try await MeetingStore.shared.createMeeting(meeting)

        // Parse body content
        let body = extractBody(content)

        // Extract and save summary (everything before ## Notes and ## Transcript)
        let summaryContent = extractSummary(body)
        if !summaryContent.isEmpty {
            let summary = AISummary(meetingId: meetingId, summaryType: "general", content: summaryContent, modelUsed: "imported")
            try await MeetingStore.shared.saveSummary(summary)
        }

        // Extract and save notes
        let notes = extractNotes(body)
        for (text, timestamp) in notes {
            let note = UserNote(meetingId: meetingId, text: text, timestamp: timestamp)
            try await MeetingStore.shared.addNote(note)
        }

        // Extract and save transcript segments
        let segments = extractTranscript(body, meetingId: meetingId)
        if !segments.isEmpty {
            try await MeetingStore.shared.addTranscriptSegments(segments)
        }

        logger.info("Imported meeting: \(title) (\(meetingId.uuidString.prefix(8)))")
        return true
    }

    // MARK: - Parsing

    private func parseFrontmatter(_ content: String) -> [String: String]? {
        guard content.hasPrefix("---\n") else { return nil }
        let parts = content.dropFirst(4).components(separatedBy: "\n---")
        guard parts.count >= 2 else { return nil }

        let yamlBlock = parts[0]
        var result: [String: String] = [:]
        for line in yamlBlock.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result.isEmpty ? nil : result
    }

    private func extractBody(_ content: String) -> String {
        let parts = content.components(separatedBy: "\n---\n")
        guard parts.count >= 2 else { return content }
        return parts.dropFirst().joined(separator: "\n---\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractSummary(_ body: String) -> String {
        // Summary is everything after the # Title and before ## Notes or ## Transcript
        var lines = body.components(separatedBy: "\n")

        // Skip the title line
        if let firstHash = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            lines = Array(lines.dropFirst(firstHash + 1))
        }

        var summaryLines: [String] = []
        for line in lines {
            if line.hasPrefix("## Notes") || line.hasPrefix("## Transcript") {
                break
            }
            summaryLines.append(line)
        }
        return summaryLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractNotes(_ body: String) -> [(String, TimeInterval)] {
        guard let notesRange = body.range(of: "## Notes\n") else { return [] }
        let afterNotes = String(body[notesRange.upperBound...])
        var results: [(String, TimeInterval)] = []

        for line in afterNotes.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { break } // Next section
            // Parse: - **[3:45 PM]** Note text here
            if line.hasPrefix("- **[") {
                let withoutPrefix = String(line.dropFirst(5)) // drop "- **["
                if let closeBracket = withoutPrefix.firstIndex(of: "]") {
                    let noteText = String(withoutPrefix[withoutPrefix.index(closeBracket, offsetBy: 3)...]) // skip "]** "
                    results.append((noteText, Date().timeIntervalSinceReferenceDate))
                }
            }
        }
        return results
    }

    private func extractTranscript(_ body: String, meetingId: UUID) -> [TranscriptSegment] {
        guard let transcriptRange = body.range(of: "## Transcript\n") else { return [] }
        let afterTranscript = String(body[transcriptRange.upperBound...])
        var segments: [TranscriptSegment] = []
        var timeOffset: TimeInterval = 0

        for line in afterTranscript.components(separatedBy: "\n\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("## ") { break } // Next section

            // Parse: **Speaker:** text
            if trimmed.hasPrefix("**") {
                if let colonStarIdx = trimmed.range(of: ":**") {
                    let speaker = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<colonStarIdx.lowerBound])
                    let text = String(trimmed[colonStarIdx.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        let seg = TranscriptSegment(
                            meetingId: meetingId,
                            speaker: speaker,
                            speakerIndex: speaker == "You" ? 0 : nil,
                            text: text,
                            startTime: timeOffset,
                            endTime: timeOffset + 5,
                            confidence: 1.0,
                            isFinal: true
                        )
                        segments.append(seg)
                        timeOffset += 5
                    }
                }
            }
        }
        return segments
    }

    private func parseDuration(_ str: String) -> TimeInterval? {
        // Parse "45m", "1h 30m", etc.
        var total: TimeInterval = 0
        let scanner = Scanner(string: str)
        while !scanner.isAtEnd {
            if let num = scanner.scanDouble() {
                if scanner.scanString("h") != nil {
                    total += num * 3600
                } else if scanner.scanString("m") != nil {
                    total += num * 60
                } else if scanner.scanString("s") != nil {
                    total += num
                }
            } else {
                break
            }
            _ = scanner.scanCharacters(from: .whitespaces)
        }
        return total > 0 ? total : nil
    }
}
