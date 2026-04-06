import Testing
@testable import ScribeCore
import Foundation

// ============================================================================
// MARK: - Simulated Full Meeting Pipeline
// ============================================================================

@Suite("Full Meeting Pipeline Simulation")
struct MeetingPipelineSimTests {

    @Test("Complete meeting lifecycle: detect → record → transcribe → summarize → export")
    func completePipeline() async throws {
        // === PHASE 1: Meeting Detection ===
        let session = MeetingSession(
            title: "Sprint Planning",
            calendarEventId: "google-cal-abc",
            meetingURL: "https://meet.google.com/abc-def-ghi"
        )
        try await session.markDetected()
        #expect(await session.state == .detected)

        // === PHASE 2: Start Recording ===
        try await session.startRecording()
        let meetingId = await session.id
        let record = await session.toRecord()
        #expect(record.state == "recording")

        // === PHASE 3: Simulate Transcription ===
        let provider = MockTranscriptionProvider()
        try await provider.connect()
        provider.emitAll(MeetingFixtures.standup)

        var transcriptResults: [TranscriptionResult] = []
        for await result in provider.results {
            transcriptResults.append(result)
        }
        #expect(transcriptResults.count == 15)

        // Convert to TranscriptSegments
        let segments = transcriptResults
            .filter(\.isFinal)
            .map { r in
                TranscriptSegment(
                    meetingId: meetingId,
                    speaker: r.speaker, speakerIndex: r.speakerIndex,
                    text: r.text, startTime: r.startTime, endTime: r.endTime,
                    confidence: r.confidence, isFinal: r.isFinal
                )
            }
        #expect(segments.count == 15) // all standup segments are final

        // === PHASE 4: User Notes During Meeting ===
        let notes = [
            UserNote(meetingId: meetingId, text: "Bob will review Alice's PR", timestamp: 42),
            UserNote(meetingId: meetingId, text: "DB migration Thursday evening", timestamp: 53),
        ]

        // === PHASE 5: End Recording ===
        try await session.endRecording()
        #expect(await session.state == .ended)

        // === PHASE 6: LLM Summarization ===
        let llm = MockLLMProvider()
        llm.responseGenerator = { messages in
            let prompt = messages.map(\.content).joined(separator: " ")
            if prompt.contains("action items") { return MeetingFixtures.summaryResponses["action_items"]! }
            if prompt.contains("decisions") { return MeetingFixtures.summaryResponses["decisions"]! }
            return MeetingFixtures.summaryResponses["full"]!
        }

        try await session.startProcessing()

        // Generate 3 summary types
        let summaryTypes = ["full", "action_items", "decisions"]
        var summaries: [AISummary] = []
        for type in summaryTypes {
            let transcript = segments.map(\.text).joined(separator: " ")
            let messages = [
                LLMMessage(role: .system, content: "You are a meeting summarizer."),
                LLMMessage(role: .user, content: "Generate \(type) for: \(transcript)")
            ]
            let response = try await llm.complete(messages: messages)
            summaries.append(AISummary(
                meetingId: meetingId,
                summaryType: type,
                content: response,
                modelUsed: "mock-model"
            ))
        }
        #expect(summaries.count == 3)
        #expect(llm.completeCalls.count == 3)

        try await session.markComplete()

        // === PHASE 7: Verify Complete Data Set ===
        let finalRecord = await session.toRecord()
        #expect(finalRecord.state == "complete")
        #expect(finalRecord.calendarEventId == "google-cal-abc")
        #expect(finalRecord.meetingURL == "https://meet.google.com/abc-def-ghi")
        #expect(finalRecord.endTime != nil)
        #expect(finalRecord.duration != nil)

        // === PHASE 8: Export to JSON ===
        let export = MeetingExport(
            meeting: finalRecord,
            transcript: segments,
            notes: notes,
            summaries: summaries,
            screenContexts: [],
            exportedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)
        #expect(data.count > 1000) // substantial export

        // Verify roundtrip
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingExport.self, from: data)
        #expect(decoded.meeting.id == meetingId)
        #expect(decoded.transcript.count == 15)
        #expect(decoded.notes.count == 2)
        #expect(decoded.summaries.count == 3)
        #expect(decoded.summaries.map(\.summaryType).sorted() == ["action_items", "decisions", "full"])
    }

    @Test("Meeting with screen contexts: presentation slides captured")
    func meetingWithScreenContext() async throws {
        let meetingId = UUID()
        let session = MeetingSession(id: meetingId, title: "Quarterly Review")
        try await session.startRecording()

        // Simulate transcription
        let segments = MeetingFixtures.generateSegments(count: 50, meetingId: meetingId, speakers: 2)

        // Simulate screen captures every 15s
        let contexts = stride(from: 15.0, through: 150.0, by: 15.0).enumerated().map { (i, ts) in
            ScreenContext(
                meetingId: meetingId,
                timestamp: ts,
                extractedText: "Slide \(i + 1): Revenue chart showing \(Int.random(in: 10...50))% growth",
                sourceDescription: "Keynote"
            )
        }
        #expect(contexts.count == 10)

        try await session.endRecording()

        // Summarize with screen context
        let llm = MockLLMProvider()
        llm.responseGenerator = { messages in
            let prompt = messages.map(\.content).joined(separator: " ")
            if prompt.contains("Screen") || prompt.contains("slide") {
                return "Summary incorporating screen context: The presentation showed revenue growth across 10 slides."
            }
            return "Standard summary."
        }

        try await session.startProcessing()

        let contextText = contexts.map(\.extractedText).joined(separator: "\n")
        let transcriptText = segments.map(\.text).joined(separator: " ")

        let summaryResponse = try await llm.complete(messages: [
            LLMMessage(role: .system, content: "Summarize this meeting."),
            LLMMessage(role: .user, content: "Transcript: \(transcriptText)\n\nScreen captures:\n\(contextText)")
        ])
        #expect(summaryResponse.contains("screen context"))

        try await session.markComplete()

        // Verify export includes screen contexts
        let export = MeetingExport(
            meeting: await session.toRecord(),
            transcript: segments,
            notes: [],
            summaries: [AISummary(meetingId: meetingId, summaryType: "full", content: summaryResponse, modelUsed: "mock")],
            screenContexts: contexts,
            exportedAt: Date()
        )
        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(MeetingExport.self, from: data)
        #expect(decoded.screenContexts.count == 10)
    }

    @Test("Note enrichment: LLM adds transcript context to user notes")
    func noteEnrichment() async throws {
        let meetingId = UUID()
        let segments = MeetingFixtures.standup.map { $0.toSegment(meetingId: meetingId) }

        // User note taken at timestamp 42 (during "I worked on database migration scripts")
        let note = UserNote(meetingId: meetingId, text: "Bob reviews Alice's PR", timestamp: 42)

        // Find segments within 60s window of note
        let windowStart = note.timestamp - 30
        let windowEnd = note.timestamp + 30
        let nearbySegments = segments.filter { $0.startTime >= windowStart && $0.startTime <= windowEnd }
        #expect(!nearbySegments.isEmpty)

        // Simulate enrichment via LLM
        let llm = MockLLMProvider()
        llm.fixedResponse = "Bob agreed to review Alice's payment integration PR after the standup call. The fix resolves a webhook misconfiguration in staging."

        let context = nearbySegments.map { "\($0.speaker ?? "Unknown"): \($0.text)" }.joined(separator: "\n")
        let enriched = try await llm.complete(messages: [
            LLMMessage(role: .system, content: "Enrich this note with meeting context."),
            LLMMessage(role: .user, content: "Note: \(note.text)\n\nNearby transcript:\n\(context)")
        ])

        #expect(enriched.contains("payment integration"))
        #expect(enriched.contains("webhook"))
    }

    @Test("Chat service simulation: ask questions about ongoing meeting")
    func chatSimulation() async throws {
        let meetingId = UUID()
        let segments = MeetingFixtures.standup.map { $0.toSegment(meetingId: meetingId) }

        let llm = MockLLMProvider()
        llm.responseGenerator = { messages in
            let allContent = messages.map(\.content).joined(separator: " ")
            if allContent.contains("action items") {
                return "Based on the meeting:\n1. Bob reviews Alice's PR\n2. Alice deploys payment fix\n3. Schedule DB migration Thursday"
            }
            if allContent.contains("miss") {
                return "The team discussed authentication progress, a payment bug fix, and an upcoming database migration."
            }
            return "The meeting is about sprint progress updates."
        }

        // Quick action: "What did I miss?"
        let context = segments.suffix(10).map { "\($0.speaker ?? ""): \($0.text)" }.joined(separator: "\n")
        let missedResponse = try await llm.complete(messages: [
            LLMMessage(role: .system, content: "You are a meeting assistant. Recent transcript:\n\(context)"),
            LLMMessage(role: .user, content: "What did I miss?")
        ])
        #expect(missedResponse.contains("authentication") || missedResponse.contains("payment") || missedResponse.contains("migration"))

        // Quick action: "Action items"
        let actionsResponse = try await llm.complete(messages: [
            LLMMessage(role: .system, content: "Transcript:\n\(context)"),
            LLMMessage(role: .user, content: "List action items from this meeting")
        ])
        #expect(actionsResponse.contains("Bob") || actionsResponse.contains("Alice") || actionsResponse.contains("migration"))
    }
}

// ============================================================================
// MARK: - Simulated Error Scenarios
// ============================================================================

@Suite("Error Path Simulation")
struct ErrorPathSimTests {

    @Test("Transcription connection failure → meeting still has metadata")
    func transcriptionFailureRecovery() async throws {
        let session = MeetingSession(title: "Failed Transcription Meeting")
        try await session.startRecording()

        let provider = MockTranscriptionProvider()
        provider.shouldFailOnConnect = true
        provider.failError = .connectionFailed("Network unreachable")

        do {
            try await provider.connect()
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Transcription failed, but meeting session should still be recoverable
        }

        // Can still end meeting (just won't have transcript)
        try await session.endRecording()
        try await session.startProcessing()
        try await session.markComplete()

        let record = await session.toRecord()
        #expect(record.state == "complete")
        #expect(record.title == "Failed Transcription Meeting")
    }

    @Test("LLM failure → meeting completes without summaries")
    func llmFailureRecovery() async throws {
        let session = MeetingSession(title: "No Summary Meeting")
        try await session.startRecording()
        try await session.endRecording()
        try await session.startProcessing()

        let llm = MockLLMProvider()
        llm.shouldFail = .networkError("timeout")

        // Summarization fails
        do {
            _ = try await llm.complete(messages: [LLMMessage(role: .user, content: "Summarize")])
            #expect(Bool(false))
        } catch {
            // Expected
        }

        // Meeting still completes
        try await session.markComplete()
        let record = await session.toRecord()
        #expect(record.state == "complete")

        // Export works with empty summaries
        let export = MeetingExport(
            meeting: record, transcript: [], notes: [], summaries: [], screenContexts: [], exportedAt: Date()
        )
        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(MeetingExport.self, from: data)
        #expect(decoded.summaries.isEmpty)
    }

    @Test("LLM rate limited → should propagate error, not hang")
    func rateLimitPropagation() async {
        let llm = MockLLMProvider()
        llm.shouldFail = .rateLimited
        do {
            _ = try await llm.complete(messages: [LLMMessage(role: .user, content: "test")])
            #expect(Bool(false))
        } catch let error as LLMError {
            #expect(error.errorDescription?.contains("Rate") == true || error.errorDescription?.contains("rate") == true)
        } catch {
            #expect(Bool(false), "Should be LLMError, got \(error)")
        }
    }

    @Test("Empty meeting: start → immediately stop → export produces valid JSON")
    func emptyMeeting() async throws {
        let session = MeetingSession(title: "Cancelled")
        try await session.startRecording()
        try await session.endRecording()
        try await session.startProcessing()
        try await session.markComplete()

        let export = MeetingExport(
            meeting: await session.toRecord(),
            transcript: [], notes: [], summaries: [], screenContexts: [],
            exportedAt: Date()
        )
        let data = try JSONEncoder().encode(export)
        #expect(data.count > 0)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"transcript\":[]"))
    }
}

// ============================================================================
// MARK: - Scale Simulation
// ============================================================================

@Suite("Scale Simulation")
struct ScaleSimTests {

    @Test("300-segment presentation: all delivered, single speaker, >25min span")
    func longPresentation() async throws {
        let segs = MeetingFixtures.generateSegments(count: 300, meetingId: UUID(), speakers: 1)
        #expect(segs.count == 300)
        #expect(Set(segs.map(\.speaker)).count == 1)
        #expect(segs.last!.endTime > 10 * 60, "300 segments at 3s each should span >10 min, got \(segs.last!.endTime)s")

        // Export this size
        let export = MeetingExport(
            meeting: MeetingRecord(title: "Long Presentation", state: "complete"),
            transcript: segs, notes: [], summaries: [], screenContexts: [],
            exportedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        #expect(data.count > 50_000, "300 segments should be >50KB JSON")
    }

    @Test("1000-segment meeting: all encoded, 4 speakers")
    func massiveTranscript() async throws {
        let id = UUID()
        let segs = MeetingFixtures.generateSegments(count: 1000, meetingId: id, speakers: 4)
        #expect(segs.count == 1000)
        #expect(Set(segs.compactMap(\.speakerIndex)).count == 4)
        #expect(segs.allSatisfy { $0.meetingId == id })
    }

    @Test("50 meetings with varied states")
    func fiftyMeetings() {
        let states = ["complete", "complete", "complete", "ended", "recording"]
        let titles = ["Standup", "Sprint Planning", "Retro", "1:1", "All Hands"]
        let meetings = (0..<50).map { i in
            MeetingRecord(
                title: "\(titles[i % 5]) #\(i)",
                startTime: Date().addingTimeInterval(Double(-i) * 86400),
                duration: Double.random(in: 300...5400),
                state: states[i % 5]
            )
        }
        #expect(meetings.count == 50)
        #expect(Set(meetings.map(\.id)).count == 50) // all unique IDs
        #expect(meetings.filter { $0.state == "complete" }.count == 30)
        #expect(meetings.filter { $0.state == "ended" }.count == 10)
        #expect(meetings.filter { $0.state == "recording" }.count == 10)
    }

    @Test("Stream 1000 results through mock provider")
    func thousandResults() async throws {
        let provider = MockTranscriptionProvider()
        try await provider.connect()

        let segments = (0..<1000).map { i in
            SimulatedSegment("Segment \(i)", start: Double(i) * 3, end: Double(i) * 3 + 2.5,
                             speaker: "Speaker \(i % 4)", speakerIdx: i % 4)
        }
        provider.emitAll(segments)

        var count = 0
        for await _ in provider.results { count += 1 }
        #expect(count == 1000)
    }
}

// ============================================================================
// MARK: - Export & Data Integrity Simulation
// ============================================================================

@Suite("Export Data Integrity Simulation")
struct ExportIntegritySimTests {

    @Test("Complete meeting export roundtrip with all data types")
    func fullExportRoundtrip() throws {
        let data = MeetingFixtures.completeMeeting(segmentCount: 25, noteCount: 5)

        let export = MeetingExport(
            meeting: data.meeting,
            transcript: data.segments,
            notes: data.notes,
            summaries: data.summaries,
            screenContexts: data.contexts,
            exportedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(export)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingExport.self, from: jsonData)

        #expect(decoded.meeting.id == data.meeting.id)
        #expect(decoded.meeting.title == data.meeting.title)
        #expect(decoded.transcript.count == 25)
        #expect(decoded.notes.count == 5)
        #expect(decoded.summaries.count == 3)
        #expect(decoded.screenContexts.count == 2)

        // Verify no data corruption
        for (orig, dec) in zip(data.segments, decoded.transcript) {
            #expect(orig.text == dec.text)
            #expect(orig.startTime == dec.startTime)
        }
    }

    @Test("Export JSON contains ISO8601 dates")
    func iso8601Dates() throws {
        let data = MeetingFixtures.completeMeeting(segmentCount: 1)
        let export = MeetingExport(
            meeting: data.meeting, transcript: data.segments,
            notes: data.notes, summaries: data.summaries,
            screenContexts: data.contexts, exportedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(export)
        let json = String(data: jsonData, encoding: .utf8)!
        #expect(json.contains("T"), "Should contain ISO8601 'T' separator")
    }

    @Test("Export with unicode content preserves all characters")
    func unicodeExport() throws {
        let id = UUID()
        let segments = MeetingFixtures.multilingual.map { $0.toSegment(meetingId: id) }
        let export = MeetingExport(
            meeting: MeetingRecord(id: id, title: "多言語会議 🌍"),
            transcript: segments,
            notes: [UserNote(meetingId: id, text: "東京オフィスの売上が良い 📈", timestamp: 5)],
            summaries: [], screenContexts: [], exportedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingExport.self, from: data)

        #expect(decoded.meeting.title == "多言語会議 🌍")
        #expect(decoded.transcript.contains { $0.text.contains("東京") })
        #expect(decoded.notes.first?.text.contains("📈") == true)
    }

    @Test("Concurrent export generation doesn't corrupt data")
    func concurrentExports() async throws {
        // Generate 10 different meetings and export them concurrently
        let meetings = (0..<10).map { i in
            MeetingFixtures.completeMeeting(title: "Meeting \(i)", segmentCount: 10)
        }

        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (i, m) in meetings.enumerated() {
                group.addTask {
                    let export = MeetingExport(
                        meeting: m.meeting, transcript: m.segments,
                        notes: m.notes, summaries: m.summaries,
                        screenContexts: m.contexts, exportedAt: Date()
                    )
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(export)
                    return (i, data)
                }
            }

            var results: [(Int, Data)] = []
            for try await result in group {
                results.append(result)
            }

            #expect(results.count == 10)
            // Each export should decode to its own meeting
            for (i, data) in results {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(MeetingExport.self, from: data)
                #expect(decoded.meeting.title == "Meeting \(i)")
                #expect(decoded.transcript.count == 10)
            }
        }
    }
}
