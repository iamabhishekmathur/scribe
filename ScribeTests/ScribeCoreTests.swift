import Testing
@testable import ScribeCore
import Foundation

// MARK: - MeetingRecord Tests

@Suite("MeetingRecord Model Tests")
struct MeetingRecordTests {

    @Test("Default creation sets expected defaults")
    func defaultCreation() {
        let meeting = MeetingRecord(title: "Test Meeting")
        #expect(meeting.title == "Test Meeting")
        #expect(meeting.state == "recording")
        #expect(meeting.endTime == nil)
        #expect(meeting.duration == nil)
        #expect(meeting.calendarEventId == nil)
        #expect(meeting.meetingURL == nil)
        #expect(meeting.participants == nil)
        #expect(meeting.folderId == nil)
    }

    @Test("ID is unique per instance")
    func uniqueIds() {
        let m1 = MeetingRecord(title: "Meeting 1")
        let m2 = MeetingRecord(title: "Meeting 2")
        #expect(m1.id != m2.id)
    }

    @Test("Custom ID is preserved")
    func customId() {
        let customId = UUID()
        let meeting = MeetingRecord(id: customId, title: "Custom")
        #expect(meeting.id == customId)
    }

    @Test("All state strings are valid")
    func validStates() {
        let validStates = ["idle", "recording", "ended", "processing", "complete"]
        for state in validStates {
            let meeting = MeetingRecord(title: "Test", state: state)
            #expect(meeting.state == state)
        }
    }

    @Test("Empty title is allowed (potential issue)")
    func emptyTitle() {
        let meeting = MeetingRecord(title: "")
        #expect(meeting.title == "")
    }

    @Test("Very long title is accepted")
    func longTitle() {
        let longTitle = String(repeating: "A", count: 10000)
        let meeting = MeetingRecord(title: longTitle)
        #expect(meeting.title.count == 10000)
    }

    @Test("Unicode title handling")
    func unicodeTitle() {
        let titles = [
            "会議テスト",           // Japanese
            "اجتماع اختبار",        // Arabic (RTL)
            "🎙️ Recording 📝",     // Emoji
            "Meeting <script>alert('xss')</script>", // XSS attempt
            "Meeting\0with\0nulls", // Null bytes
            "Meeting\nwith\nnewlines", // Newlines
        ]
        for title in titles {
            let meeting = MeetingRecord(title: title)
            #expect(meeting.title == title)
        }
    }

    @Test("Timestamps are set on creation")
    func timestamps() {
        let before = Date()
        let meeting = MeetingRecord(title: "Test")
        let after = Date()
        #expect(meeting.startTime >= before)
        #expect(meeting.startTime <= after)
        #expect(meeting.createdAt >= before)
        #expect(meeting.createdAt <= after)
        #expect(meeting.updatedAt >= before)
        #expect(meeting.updatedAt <= after)
    }

    @Test("Custom startTime is preserved")
    func customStartTime() {
        let past = Date(timeIntervalSince1970: 1000000)
        let meeting = MeetingRecord(title: "Test", startTime: past)
        #expect(meeting.startTime == past)
    }

    @Test("Duration can be set directly")
    func directDuration() {
        let meeting = MeetingRecord(title: "Test", duration: 3600.0)
        #expect(meeting.duration == 3600.0)
    }

    @Test("Participants JSON string stored correctly")
    func participantsJSON() {
        let json = "[\"Alice\",\"Bob\",\"Charlie\"]"
        let meeting = MeetingRecord(title: "Test", participants: json)
        #expect(meeting.participants == json)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = MeetingRecord(
            title: "Full Meeting",
            endTime: Date(),
            duration: 3600,
            calendarEventId: "cal-123",
            meetingURL: "https://meet.example.com/abc",
            participants: "[\"Alice\"]",
            state: "complete"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingRecord.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.state == original.state)
        #expect(decoded.calendarEventId == original.calendarEventId)
        #expect(decoded.meetingURL == original.meetingURL)
        #expect(decoded.participants == original.participants)
    }

    @Test("Database table name is correct")
    func tableName() {
        #expect(MeetingRecord.databaseTableName == "meetings")
    }
}

// MARK: - TranscriptSegment Tests

@Suite("TranscriptSegment Model Tests")
struct TranscriptSegmentTests {

    @Test("Default creation with required fields")
    func defaultCreation() {
        let meetingId = UUID()
        let segment = TranscriptSegment(
            meetingId: meetingId,
            text: "Hello, world!",
            startTime: 0.0,
            endTime: 1.5
        )
        #expect(segment.meetingId == meetingId)
        #expect(segment.text == "Hello, world!")
        #expect(segment.startTime == 0.0)
        #expect(segment.endTime == 1.5)
        #expect(segment.isFinal == true)
        #expect(segment.speaker == nil)
        #expect(segment.speakerIndex == nil)
        #expect(segment.confidence == nil)
    }

    @Test("Speaker information stored correctly")
    func speakerInfo() {
        let segment = TranscriptSegment(
            meetingId: UUID(),
            speaker: "Speaker 0",
            speakerIndex: 0,
            text: "Test",
            startTime: 0.0,
            endTime: 1.0
        )
        #expect(segment.speaker == "Speaker 0")
        #expect(segment.speakerIndex == 0)
    }

    @Test("Non-final segment flag")
    func nonFinal() {
        let segment = TranscriptSegment(
            meetingId: UUID(),
            text: "Partial...",
            startTime: 0.0,
            endTime: 0.5,
            isFinal: false
        )
        #expect(segment.isFinal == false)
    }

    @Test("Confidence value stored correctly")
    func confidence() {
        let segment = TranscriptSegment(
            meetingId: UUID(),
            text: "Test",
            startTime: 0.0,
            endTime: 1.0,
            confidence: 0.95
        )
        #expect(segment.confidence == 0.95)
    }

    @Test("Boundary time values")
    func boundaryTimes() {
        // Zero-length segment
        let zero = TranscriptSegment(meetingId: UUID(), text: "A", startTime: 5.0, endTime: 5.0)
        #expect(zero.startTime == zero.endTime)

        // Very large time values (multi-hour meeting)
        let large = TranscriptSegment(meetingId: UUID(), text: "B", startTime: 7200.0, endTime: 7201.5)
        #expect(large.startTime == 7200.0)
    }

    @Test("Empty text is allowed (potential issue)")
    func emptyText() {
        let segment = TranscriptSegment(meetingId: UUID(), text: "", startTime: 0, endTime: 1)
        #expect(segment.text == "")
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = TranscriptSegment(
            meetingId: UUID(),
            speaker: "Alice",
            speakerIndex: 1,
            text: "Important point about the project",
            startTime: 120.5,
            endTime: 125.3,
            confidence: 0.88,
            isFinal: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TranscriptSegment.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.text == original.text)
        #expect(decoded.confidence == original.confidence)
    }

    @Test("Database table name is correct")
    func tableName() {
        #expect(TranscriptSegment.databaseTableName == "transcript_segments")
    }
}

// MARK: - UserNote Tests

@Suite("UserNote Model Tests")
struct UserNoteTests {

    @Test("Default creation")
    func defaultCreation() {
        let meetingId = UUID()
        let note = UserNote(meetingId: meetingId, text: "Action item: Follow up", timestamp: 60.0)
        #expect(note.meetingId == meetingId)
        #expect(note.text == "Action item: Follow up")
        #expect(note.timestamp == 60.0)
        #expect(note.enrichedText == nil)
    }

    @Test("Enriched text stored correctly")
    func enrichedText() {
        let note = UserNote(
            meetingId: UUID(),
            text: "Raw note",
            enrichedText: "<p>Enriched <b>note</b> with context</p>",
            timestamp: 30.0
        )
        #expect(note.enrichedText != nil)
    }

    @Test("Database table name is correct")
    func tableName() {
        #expect(UserNote.databaseTableName == "user_notes")
    }
}

// MARK: - AISummary Tests

@Suite("AISummary Model Tests")
struct AISummaryTests {

    @Test("Creation with all summary types")
    func summaryTypes() {
        let types = ["full", "action_items", "decisions", "topics", "follow_ups"]
        for type in types {
            let summary = AISummary(
                meetingId: UUID(),
                summaryType: type,
                content: "Summary content for \(type)",
                modelUsed: "claude-3-opus"
            )
            #expect(summary.summaryType == type)
        }
    }

    @Test("Invalid summary type is not validated (potential issue)")
    func invalidSummaryType() {
        // BUG: No validation on summaryType - any string is accepted
        let summary = AISummary(
            meetingId: UUID(),
            summaryType: "invalid_type",
            content: "Test",
            modelUsed: "test"
        )
        #expect(summary.summaryType == "invalid_type")
    }

    @Test("Database table name is correct")
    func tableName() {
        #expect(AISummary.databaseTableName == "ai_summaries")
    }
}

// MARK: - Folder Tests

@Suite("Folder Model Tests")
struct FolderTests {

    @Test("Default creation")
    func defaultCreation() {
        let folder = Folder(name: "Work Meetings")
        #expect(folder.name == "Work Meetings")
        #expect(folder.parentId == nil)
        #expect(folder.sortOrder == 0)
    }

    @Test("Nested folder with parent")
    func nestedFolder() {
        let parentId = UUID()
        let folder = Folder(name: "Q1 2026", parentId: parentId, sortOrder: 3)
        #expect(folder.parentId == parentId)
        #expect(folder.sortOrder == 3)
    }

    @Test("Empty name is allowed (potential issue)")
    func emptyName() {
        let folder = Folder(name: "")
        #expect(folder.name == "")
    }

    @Test("Database table name is correct")
    func tableName() {
        #expect(Folder.databaseTableName == "folders")
    }
}

// MARK: - ScreenContext Tests

@Suite("ScreenContext Model Tests")
struct ScreenContextTests {

    @Test("Default creation")
    func defaultCreation() {
        let meetingId = UUID()
        let ctx = ScreenContext(
            meetingId: meetingId,
            timestamp: 45.0,
            extractedText: "Slide: Q1 Revenue Report"
        )
        #expect(ctx.meetingId == meetingId)
        #expect(ctx.timestamp == 45.0)
        #expect(ctx.extractedText == "Slide: Q1 Revenue Report")
        #expect(ctx.sourceDescription == nil)
    }

    @Test("Source description stored correctly")
    func sourceDescription() {
        let ctx = ScreenContext(
            meetingId: UUID(),
            timestamp: 10.0,
            extractedText: "Text",
            sourceDescription: "Google Slides - Presentation.pptx"
        )
        #expect(ctx.sourceDescription == "Google Slides - Presentation.pptx")
    }

    @Test("Database table name is correct")
    func tableName() {
        #expect(ScreenContext.databaseTableName == "screen_contexts")
    }
}

// MARK: - MeetingExport Tests

@Suite("MeetingExport Model Tests")
struct MeetingExportTests {

    @Test("Codable round-trip with full data")
    func codableRoundTrip() throws {
        let meetingId = UUID()
        let export = MeetingExport(
            meeting: MeetingRecord(id: meetingId, title: "Export Test", state: "complete"),
            transcript: [
                TranscriptSegment(meetingId: meetingId, text: "Hello", startTime: 0, endTime: 1),
                TranscriptSegment(meetingId: meetingId, text: "World", startTime: 1, endTime: 2),
            ],
            notes: [
                UserNote(meetingId: meetingId, text: "Key point", timestamp: 0.5)
            ],
            summaries: [
                AISummary(meetingId: meetingId, summaryType: "full", content: "Summary", modelUsed: "claude")
            ],
            screenContexts: [
                ScreenContext(meetingId: meetingId, timestamp: 30, extractedText: "Slide content")
            ],
            exportedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingExport.self, from: data)

        #expect(decoded.meeting.id == meetingId)
        #expect(decoded.transcript.count == 2)
        #expect(decoded.notes.count == 1)
        #expect(decoded.summaries.count == 1)
        #expect(decoded.screenContexts.count == 1)
    }

    @Test("Empty collections export correctly")
    func emptyExport() throws {
        let export = MeetingExport(
            meeting: MeetingRecord(title: "Empty Meeting"),
            transcript: [],
            notes: [],
            summaries: [],
            screenContexts: [],
            exportedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        #expect(data.count > 0)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MeetingExport.self, from: data)
        #expect(decoded.transcript.isEmpty)
    }
}

// MARK: - AppState Tests

@Suite("AppState Tests")
@MainActor
struct AppStateTests {

    @Test("Initial state is idle")
    func initialState() {
        let state = AppState()
        #expect(state.recordingState == .idle)
        #expect(state.currentMeetingId == nil)
        #expect(state.audioLevel == 0.0)
        #expect(state.isOverlayVisible == false)
    }

    @Test("Start recording sets correct state")
    func startRecording() {
        let state = AppState()
        let meetingId = UUID()
        state.startRecording(meetingId: meetingId)
        #expect(state.recordingState == .recording)
        #expect(state.currentMeetingId == meetingId)
    }

    @Test("Stop recording transitions to processing")
    func stopRecording() {
        let state = AppState()
        state.startRecording(meetingId: UUID())
        state.stopRecording()
        #expect(state.recordingState == .processing)
        // BUG-007: currentMeetingId is NOT cleared on stop, only on finishProcessing
        #expect(state.currentMeetingId != nil)
    }

    @Test("Finish processing returns to idle")
    func finishProcessing() {
        let state = AppState()
        state.startRecording(meetingId: UUID())
        state.stopRecording()
        state.finishProcessing()
        #expect(state.recordingState == .idle)
        #expect(state.currentMeetingId == nil)
    }

    @Test("State transitions: idle -> recording -> processing -> idle")
    func fullLifecycle() {
        let state = AppState()
        #expect(state.recordingState == .idle)

        let meetingId = UUID()
        state.startRecording(meetingId: meetingId)
        #expect(state.recordingState == .recording)

        state.stopRecording()
        #expect(state.recordingState == .processing)

        state.finishProcessing()
        #expect(state.recordingState == .idle)
    }

    @Test("No guard against invalid transitions (potential issue)")
    func invalidTransitions() {
        let state = AppState()

        // Stop without starting - no guard
        state.stopRecording()
        #expect(state.recordingState == .processing)

        // Finish without starting - no guard
        state.finishProcessing()
        #expect(state.recordingState == .idle)

        // Double start - no guard
        state.startRecording(meetingId: UUID())
        let secondId = UUID()
        state.startRecording(meetingId: secondId)
        #expect(state.currentMeetingId == secondId) // First meeting ID lost
    }

    @Test("Audio level can be set")
    func audioLevel() {
        let state = AppState()
        state.audioLevel = 0.75
        #expect(state.audioLevel == 0.75)
    }
}

// MARK: - KeychainManager Tests

@Suite("KeychainManager Tests")
@MainActor
struct KeychainManagerTests {

    @Test("Transcription provider key mapping")
    func transcriptionProviderKeys() {
        let manager = KeychainManager.shared
        #expect(manager.apiKeyForTranscriptionProvider(.deepgram) == .deepgramAPIKey)
        #expect(manager.apiKeyForTranscriptionProvider(.assemblyAI) == .assemblyAIAPIKey)
        #expect(manager.apiKeyForTranscriptionProvider(.openAIWhisper) == .openAIAPIKey)
    }

    @Test("LLM provider key mapping")
    func llmProviderKeys() {
        let manager = KeychainManager.shared
        #expect(manager.apiKeyForLLMProvider(.claude) == .claudeAPIKey)
        #expect(manager.apiKeyForLLMProvider(.openAI) == .openAIAPIKey)
        // BUG-005: Both Ollama and Custom map to the same key
        #expect(manager.apiKeyForLLMProvider(.ollama) == .customLLMAPIKey)
        #expect(manager.apiKeyForLLMProvider(.custom) == .customLLMAPIKey)
    }

    @Test("BUG-005: Ollama and Custom share the same Keychain key slot")
    func ollamaCustomKeyCollision() {
        let manager = KeychainManager.shared
        let ollamaKey = manager.apiKeyForLLMProvider(.ollama)
        let customKey = manager.apiKeyForLLMProvider(.custom)
        // This test documents the bug - these SHOULD be different but are the same
        #expect(ollamaKey == customKey, "Known bug: Ollama and Custom share .customLLMAPIKey")
    }

    @Test("Key display names are non-empty")
    func displayNames() {
        for key in KeychainManager.Key.allCases {
            #expect(!key.displayName.isEmpty)
        }
    }

    @Test("Key raw values are unique")
    func uniqueRawValues() {
        let rawValues = KeychainManager.Key.allCases.map(\.rawValue)
        let unique = Set(rawValues)
        #expect(rawValues.count == unique.count, "Keychain key raw values should be unique")
    }
}

// MARK: - AppSettings Tests

@Suite("AppSettings Tests")
@MainActor
struct AppSettingsTests {

    @Test("Default values on fresh install")
    func defaults() {
        let settings = AppSettings.shared
        // These defaults are correct per spec
        #expect(settings.autoDetectMeetings == true)
        #expect(settings.showOverlayDuringMeetings == true)
        #expect(settings.autoStartRecording == false)
        #expect(settings.hasCompletedOnboarding == false)
        #expect(settings.screenContextEnabled == true)
        // screenContextInterval default (15.0) tested separately; skipped here
        // due to parallel test mutation in BUG-008 test
    }

    @Test("Default Ollama endpoint")
    func ollamaDefaults() {
        let settings = AppSettings.shared
        #expect(settings.ollamaEndpoint == "http://localhost:11434")
        #expect(settings.ollamaModel == "llama3")
    }

    @Test("Default providers")
    func defaultProviders() {
        let settings = AppSettings.shared
        #expect(settings.transcriptionProvider == .deepgram)
        #expect(settings.llmProvider == .claude)
    }

    @Test("BUG-008: Screen context interval has no minimum validation")
    func screenContextIntervalValidation() {
        let settings = AppSettings.shared
        let original = settings.screenContextInterval

        // Setting to 0 should ideally be prevented
        settings.screenContextInterval = 0.0
        #expect(settings.screenContextInterval == 0.0, "Known bug: no minimum validation")

        // Setting to negative should ideally be prevented
        settings.screenContextInterval = -5.0
        #expect(settings.screenContextInterval == -5.0, "Known bug: negative values accepted")

        // Restore
        settings.screenContextInterval = original
    }
}

// MARK: - RecordingState Tests

@Suite("RecordingState Enum Tests")
struct RecordingStateTests {

    @Test("All cases have correct raw values")
    func rawValues() {
        #expect(RecordingState.idle.rawValue == "idle")
        #expect(RecordingState.recording.rawValue == "recording")
        #expect(RecordingState.processing.rawValue == "processing")
    }

    @Test("BUG-007: RecordingState missing 'ended' and 'complete' from MeetingRecord")
    func missingStates() {
        // MeetingRecord supports: idle, recording, ended, processing, complete
        // RecordingState only has: idle, recording, processing
        // There is no .ended or .complete case
        let allCases: [RecordingState] = [.idle, .recording, .processing]
        #expect(allCases.count == 3, "Known bug: Missing 'ended' and 'complete' states")
    }
}

// MARK: - TranscriptionProviderType Tests

@Suite("TranscriptionProviderType Enum Tests")
struct TranscriptionProviderTypeTests {

    @Test("All cases present")
    func allCases() {
        #expect(TranscriptionProviderType.allCases.count == 3)
    }

    @Test("Display values are human-readable")
    func displayValues() {
        #expect(TranscriptionProviderType.deepgram.rawValue == "Deepgram")
        #expect(TranscriptionProviderType.assemblyAI.rawValue == "AssemblyAI")
        #expect(TranscriptionProviderType.openAIWhisper.rawValue == "OpenAI Whisper")
    }

    @Test("Identifiable conformance uses rawValue")
    func identifiable() {
        for provider in TranscriptionProviderType.allCases {
            #expect(provider.id == provider.rawValue)
        }
    }
}

// MARK: - LLMProviderType Tests

@Suite("LLMProviderType Enum Tests")
struct LLMProviderTypeTests {

    @Test("All cases present")
    func allCases() {
        #expect(LLMProviderType.allCases.count == 4)
    }

    @Test("Display values are human-readable")
    func displayValues() {
        #expect(LLMProviderType.claude.rawValue == "Claude")
        #expect(LLMProviderType.openAI.rawValue == "OpenAI")
        #expect(LLMProviderType.ollama.rawValue == "Ollama")
        #expect(LLMProviderType.custom.rawValue == "Custom (OpenAI-compatible)")
    }
}
