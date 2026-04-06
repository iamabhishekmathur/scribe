import Foundation
import ScribeCore

// MARK: - CLI Entry Point

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "help"
let jsonOutput = args.contains("--json")

func run() async throws {
    try await Database.shared.initialize()

    switch command {
    case "meetings":
        let limit = flagValue("--limit").flatMap(Int.init) ?? 20
        let meetings = try await MeetingStore.shared.getAllMeetings(limit: limit)
        if jsonOutput {
            printJSON(meetings.map { meetingBrief($0) })
        } else {
            if meetings.isEmpty {
                print("No meetings found.")
                return
            }
            for m in meetings {
                let date = formatDate(m.startTime)
                let dur = m.duration.map { formatDuration($0) } ?? "—"
                print("  \(m.id.uuidString)  \(date)  \(dur)  [\(m.state)]  \(m.title)")
            }
        }

    case "meeting":
        let uuid = try requireId()
        guard let meeting = try await MeetingStore.shared.getMeeting(id: uuid) else {
            printErr("Meeting not found: \(uuid)")
            return
        }
        let transcript = try await MeetingStore.shared.getTranscript(meetingId: uuid)
        let notes = try await MeetingStore.shared.getNotes(meetingId: uuid)
        let summaries = try await MeetingStore.shared.getSummaries(meetingId: uuid)
        if jsonOutput {
            printJSON([
                "meeting": meetingBrief(meeting),
                "transcript": transcript.map { segDict($0) },
                "notes": notes.map { noteDict($0) },
                "summaries": summaries.map { sumDict($0) },
            ] as [String: Any])
        } else {
            printMeetingHeader(meeting)
            if !transcript.isEmpty {
                print("\n--- Transcript ---")
                for seg in transcript {
                    let speaker = seg.speaker ?? "Unknown"
                    print("  [\(formatTimestamp(seg.startTime))] \(speaker): \(seg.text)")
                }
            }
            if !notes.isEmpty {
                print("\n--- Notes ---")
                for note in notes { print("  \(note.enrichedText ?? note.text)") }
            }
            if !summaries.isEmpty {
                print("\n--- Summaries ---")
                for s in summaries {
                    print("  [\(s.summaryType)]")
                    print("  \(s.content)\n")
                }
            }
        }

    case "transcript":
        let uuid = try requireId()
        let segments = try await MeetingStore.shared.getTranscript(meetingId: uuid)
        if jsonOutput {
            printJSON(segments.map { segDict($0) })
        } else {
            if segments.isEmpty { print("No transcript found."); return }
            for seg in segments {
                let speaker = seg.speaker ?? "Unknown"
                print("[\(formatTimestamp(seg.startTime))] \(speaker): \(seg.text)")
            }
        }

    case "summary":
        let uuid = try requireId()
        let summaries = try await MeetingStore.shared.getSummaries(meetingId: uuid)
        if jsonOutput {
            printJSON(summaries.map { sumDict($0) })
        } else {
            if summaries.isEmpty { print("No summaries found."); return }
            for s in summaries {
                print("[\(s.summaryType)]")
                print(s.content)
                print()
            }
        }

    case "actions":
        let uuid = try requireId()
        let summaries = try await MeetingStore.shared.getSummaries(meetingId: uuid)
        let items = summaries.filter { $0.summaryType == "action_items" || $0.summaryType == "decisions" }
        if jsonOutput {
            printJSON(items.map { sumDict($0) })
        } else {
            if items.isEmpty { print("No action items or decisions found."); return }
            for s in items {
                print("[\(s.summaryType)]")
                print(s.content)
                print()
            }
        }

    case "search":
        guard args.count > 2 else {
            printErr("Usage: scribe-cli search <query>")
            return
        }
        // Collect all args after "search" that aren't flags
        let query = args.dropFirst(2).filter { !$0.hasPrefix("--") }.joined(separator: " ")
        guard !query.isEmpty else { printErr("Empty query"); return }
        let limit = flagValue("--limit").flatMap(Int.init) ?? 20
        let results = try await SearchIndex.shared.search(query: query, limit: limit)
        if jsonOutput {
            printJSON(results.map { r in
                ["meetingId": r.meetingId.uuidString, "meetingTitle": r.meetingTitle,
                 "snippet": r.snippet, "source": r.source.rawValue] as [String: Any]
            })
        } else {
            if results.isEmpty { print("No results found."); return }
            for r in results {
                let snippet = r.snippet.replacingOccurrences(of: "<b>", with: "").replacingOccurrences(of: "</b>", with: "")
                print("  [\(r.source.rawValue)] \(r.meetingTitle)")
                print("    \(snippet)\n")
            }
        }

    case "folders":
        let folders = try await MeetingStore.shared.getFolders()
        if jsonOutput {
            printJSON(folders.map { ["id": $0.id.uuidString, "name": $0.name, "sortOrder": $0.sortOrder] as [String: Any] })
        } else {
            if folders.isEmpty { print("No folders."); return }
            for f in folders { print("  \(f.id.uuidString)  \(f.name)") }
        }

    case "help", "--help", "-h":
        printUsage()

    default:
        printErr("Unknown command: \(command)")
        printUsage()
    }
}

// MARK: - Helpers

func requireId() throws -> UUID {
    guard args.count > 2, let uuid = UUID(uuidString: args[2]) else {
        printErr("Usage: scribe-cli \(command) <meeting-uuid>")
        throw CLIError.missingId
    }
    return uuid
}

func flagValue(_ flag: String) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

func meetingBrief(_ m: MeetingRecord) -> [String: Any] {
    var d: [String: Any] = [
        "id": m.id.uuidString,
        "title": m.title,
        "startTime": isoString(m.startTime),
        "state": m.state,
    ]
    if let end = m.endTime { d["endTime"] = isoString(end) }
    if let dur = m.duration { d["duration"] = dur }
    return d
}

func segDict(_ s: TranscriptSegment) -> [String: Any] {
    ["speaker": s.speaker ?? "Unknown", "text": s.text, "startTime": s.startTime, "endTime": s.endTime]
}

func noteDict(_ n: UserNote) -> [String: Any] {
    var d: [String: Any] = ["text": n.text, "timestamp": n.timestamp]
    if let enriched = n.enrichedText { d["enrichedText"] = enriched }
    return d
}

func sumDict(_ s: AISummary) -> [String: Any] {
    ["type": s.summaryType, "content": s.content]
}

func printJSON(_ value: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: .prettyPrinted),
          let str = String(data: data, encoding: .utf8) else {
        printErr("JSON serialization failed")
        return
    }
    print(str)
}

func printMeetingHeader(_ m: MeetingRecord) {
    print("Title:    \(m.title)")
    print("ID:       \(m.id.uuidString)")
    print("Date:     \(formatDate(m.startTime))")
    if let dur = m.duration { print("Duration: \(formatDuration(dur))") }
    print("State:    \(m.state)")
    if let url = m.meetingURL { print("URL:      \(url)") }
}

func formatDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f.string(from: date)
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    if mins >= 60 {
        return "\(mins / 60)h \(mins % 60)m"
    }
    return "\(mins)m \(secs)s"
}

func formatTimestamp(_ t: TimeInterval) -> String {
    let mins = Int(t) / 60
    let secs = Int(t) % 60
    return String(format: "%02d:%02d", mins, secs)
}

func printErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func printUsage() {
    print("""
    Usage: scribe-cli <command> [options]

    Commands:
      meetings [--limit N]     List recent meetings
      meeting <id>             Full meeting details
      transcript <id>          Transcript only
      summary <id>             Summary only
      actions <id>             Action items + decisions
      search <query>           Search all content
      folders                  List folders
      help                     Show this help

    Options:
      --json                   Output as JSON
      --limit N                Limit results
    """)
}

enum CLIError: Error {
    case missingId
}

do {
    try await run()
} catch is CLIError {
    // Already printed usage — just exit
    exit(1)
} catch {
    printErr("Error: \(error.localizedDescription)")
    exit(1)
}
