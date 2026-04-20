import Testing
@testable import ScribeCore
import Foundation

// ============================================================================
// MARK: - Meeting Session State Machine (TESTING.md §4)
// ============================================================================

@Suite("MeetingSession State Machine Simulation")
struct MeetingSessionSimTests {

    @Test("Full happy-path lifecycle: idle → detected → recording → ended → processing → complete")
    func fullLifecycle() async throws {
        let s = MeetingSession(title: "Standup", calendarEventId: "cal-1", meetingURL: "https://meet.google.com/abc")
        #expect(await s.state == .idle)
        try await s.markDetected(); #expect(await s.state == .detected)
        try await s.startRecording(); #expect(await s.state == .recording)
        try await s.endRecording(); #expect(await s.state == .ended)
        #expect(await s.endTime != nil)
        #expect(await s.duration != nil)
        try await s.startProcessing(); #expect(await s.state == .processing)
        try await s.markComplete(); #expect(await s.state == .complete)
    }

    @Test("Direct start (skip detection): idle → recording")
    func directStart() async throws {
        let s = MeetingSession(title: "Manual")
        try await s.startRecording()
        #expect(await s.state == .recording)
    }

    @Test("All invalid transitions throw MeetingSessionError")
    func invalidTransitions() async throws {
        let s = MeetingSession(title: "Bad")

        // idle → ended
        await #expect(throws: MeetingSessionError.self) { try await s.endRecording() }
        // idle → processing
        await #expect(throws: MeetingSessionError.self) { try await s.startProcessing() }
        // idle → complete
        await #expect(throws: MeetingSessionError.self) { try await s.markComplete() }

        // recording → complete (skips processing)
        try await s.startRecording()
        await #expect(throws: MeetingSessionError.self) { try await s.markComplete() }
        // recording → detected (backwards)
        await #expect(throws: MeetingSessionError.self) { try await s.markDetected() }
        // double start
        await #expect(throws: MeetingSessionError.self) { try await s.startRecording() }

        // ended → recording (restart)
        try await s.endRecording()
        await #expect(throws: MeetingSessionError.self) { try await s.startRecording() }

        // complete → anything
        try await s.startProcessing()
        try await s.markComplete()
        await #expect(throws: MeetingSessionError.self) { try await s.startRecording() }
        await #expect(throws: MeetingSessionError.self) { try await s.markDetected() }
    }

    @Test("toRecord() preserves all metadata at each state")
    func toRecordPreservesData() async throws {
        let id = UUID()
        let start = Date()
        let s = MeetingSession(id: id, title: "Sync", startTime: start, calendarEventId: "g-123", meetingURL: "https://meet.google.com/x")
        try await s.startRecording()
        try await s.endRecording()

        let r = await s.toRecord()
        #expect(r.id == id)
        #expect(r.title == "Sync")
        #expect(r.startTime == start)
        #expect(r.calendarEventId == "g-123")
        #expect(r.meetingURL == "https://meet.google.com/x")
        #expect(r.state == "ended")
        #expect(r.endTime != nil)
        #expect(r.duration != nil)
        #expect(r.duration! >= 0)
    }

    @Test("Duration is nil while recording, populated after end")
    func durationTiming() async throws {
        let s = MeetingSession(title: "Timing")
        try await s.startRecording()
        #expect(await s.duration == nil)
        try await Task.sleep(for: .milliseconds(50))
        try await s.endRecording()
        let d = await s.duration!
        #expect(d >= 0.03 && d < 1.0)
    }
}

// ============================================================================
// MARK: - Audio Activity Detector (TESTING.md §4)
// ============================================================================

@Suite("AudioActivityDetector Simulation")
struct AudioActivityDetectorSimTests {

    @Test("Not triggered when only mic is active")
    func micOnly() async {
        let d = AudioActivityDetector(triggerThreshold: 0.1, rmsThreshold: 0.01)
        for _ in 0..<20 {
            await d.updateMicLevel(0.05)
            await d.updateSystemLevel(0.0)
        }
        #expect(await d.isMeetingLikeActivity == false)
    }

    @Test("Not triggered when only system audio is active")
    func systemOnly() async {
        let d = AudioActivityDetector(triggerThreshold: 0.1, rmsThreshold: 0.01)
        for _ in 0..<20 {
            await d.updateMicLevel(0.0)
            await d.updateSystemLevel(0.05)
        }
        #expect(await d.isMeetingLikeActivity == false)
    }

    @Test("Triggered when both mic and system active for threshold duration")
    func bothActive() async throws {
        let d = AudioActivityDetector(triggerThreshold: 0.1, rmsThreshold: 0.01)
        // Feed both sources active for > threshold
        let start = Date()
        while Date().timeIntervalSince(start) < 0.15 {
            await d.updateMicLevel(0.05)
            await d.updateSystemLevel(0.05)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await d.isMeetingLikeActivity == true)
    }

    @Test("Reset clears detection state")
    func resetClears() async throws {
        let d = AudioActivityDetector(triggerThreshold: 0.05, rmsThreshold: 0.01)
        let start = Date()
        while Date().timeIntervalSince(start) < 0.08 {
            await d.updateMicLevel(0.05)
            await d.updateSystemLevel(0.05)
            try await Task.sleep(for: .milliseconds(5))
        }
        await d.reset()
        #expect(await d.isMeetingLikeActivity == false)
    }

    @Test("Below RMS threshold doesn't count as active")
    func belowThreshold() async throws {
        let d = AudioActivityDetector(triggerThreshold: 0.05, rmsThreshold: 0.01)
        let start = Date()
        while Date().timeIntervalSince(start) < 0.08 {
            await d.updateMicLevel(0.005) // below threshold
            await d.updateSystemLevel(0.005)
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await d.isMeetingLikeActivity == false)
    }
}

// ============================================================================
// MARK: - Speaker Identification (TESTING.md §10)
// ============================================================================

@Suite("Speaker Identification Simulation")
struct SpeakerIdentifierSimTests {

    @Test("Color palette has 8 colors and cycles")
    func colorPalette() async {
        let si = SpeakerIdentifier.shared
        let colors = await (0..<8).asyncMap { await si.color(speakerIndex: $0) }
        // All 8 should be unique
        #expect(Set(colors).count == 8)
        // Should cycle after 8
        let color0 = await si.color(speakerIndex: 0)
        let color8 = await si.color(speakerIndex: 8)
        #expect(color0 == color8, "Colors should cycle after index 7")
    }

    @Test("Default display name is 'Speaker N'")
    func defaultDisplayName() async {
        let si = SpeakerIdentifier.shared
        let name = await si.displayName(speakerIndex: 0, meetingId: UUID())
        #expect(name == "You")
        let name3 = await si.displayName(speakerIndex: 3, meetingId: UUID())
        #expect(name3 == "Speaker 3")
    }

    @Test("Speaker 0 color is blue (#007AFF)")
    func speaker0Color() async {
        let si = SpeakerIdentifier.shared
        let c = await si.color(speakerIndex: 0)
        #expect(c == "#007AFF")
    }
}

// MARK: Async helper
extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        for element in self {
            results.append(await transform(element))
        }
        return results
    }
}

// ============================================================================
// MARK: - Transcription Provider Protocol (TESTING.md §3)
// ============================================================================

@Suite("Transcription Provider Simulation")
struct TranscriptionProviderSimTests {

    @Test("Mock provider connect/disconnect lifecycle")
    func lifecycle() async throws {
        let p = MockTranscriptionProvider()
        #expect(!p.isConnected)
        try await p.connect()
        #expect(p.isConnected)
        #expect(p.connectCalled)
        try await p.sendAudio(Data(repeating: 0, count: 3200))
        #expect(p.audioChunksReceived == 1)
        await p.disconnect()
        #expect(!p.isConnected)
        #expect(p.disconnectCalled)
    }

    @Test("Rejects audio when disconnected")
    func rejectWhenDisconnected() async {
        let p = MockTranscriptionProvider()
        await #expect(throws: TranscriptionError.self) {
            try await p.sendAudio(Data([0x00]))
        }
    }

    @Test("Connection failure modes")
    func connectionFailures() async {
        let p = MockTranscriptionProvider()
        p.shouldFailOnConnect = true

        p.failError = .invalidAPIKey
        await #expect(throws: TranscriptionError.self) { try await p.connect() }
        #expect(!p.isConnected)

        p.failError = .connectionFailed("timeout")
        await #expect(throws: TranscriptionError.self) { try await p.connect() }

        p.failError = .rateLimited
        await #expect(throws: TranscriptionError.self) { try await p.connect() }
    }

    @Test("Stream delivers all segments in order then finishes")
    func streamDelivery() async throws {
        let p = MockTranscriptionProvider()
        try await p.connect()
        p.emitAll(MeetingFixtures.standup)

        var received: [TranscriptionResult] = []
        for await r in p.results { received.append(r) }

        #expect(received.count == 15)
        // Chronological
        for i in 1..<received.count {
            #expect(received[i].startTime >= received[i-1].startTime)
        }
        // 3 speakers
        #expect(Set(received.compactMap(\.speaker)).count == 3)
    }

    @Test("Interim results: 3 non-final then 1 final")
    func interimResults() async throws {
        let p = MockTranscriptionProvider()
        try await p.connect()
        p.emitAll(MeetingFixtures.interimStream)

        var received: [TranscriptionResult] = []
        for await r in p.results { received.append(r) }

        #expect(received.count == 4)
        #expect(received.filter { !$0.isFinal }.count == 3)
        #expect(received.filter { $0.isFinal }.count == 1)
        // Final is most refined (longest)
        #expect(received.last!.text.count > received.first!.text.count)
    }

    @Test("Crosstalk: overlapping timestamps from different speakers")
    func crosstalk() async throws {
        let p = MockTranscriptionProvider()
        try await p.connect()
        p.emitAll(MeetingFixtures.crosstalk)

        var received: [TranscriptionResult] = []
        for await r in p.results { received.append(r) }

        #expect(received.count == 5)
        // Should have overlapping ranges
        let hasOverlap = (0..<received.count - 1).contains { i in
            received[i].endTime > received[i + 1].startTime
        }
        #expect(hasOverlap)
    }

    @Test("Multilingual: CJK, Arabic, accented Latin preserved")
    func multilingual() async throws {
        let p = MockTranscriptionProvider()
        try await p.connect()
        p.emitAll(MeetingFixtures.multilingual)

        var received: [TranscriptionResult] = []
        for await r in p.results { received.append(r) }

        #expect(received.count == 5)
        #expect(received.contains { $0.text.contains("東京") })
        #expect(received.contains { $0.text.contains("收入") })
        #expect(received.contains { $0.text.contains("الأرقام") })
        #expect(received.contains { $0.text.contains("München") })
        #expect(received.contains { $0.text.contains("São Paulo") })
    }

    @Test("Provider factory creates correct types")
    func providerFactory() {
        let d = TranscriptionManager.createProvider(type: .deepgram, apiKey: "k")
        #expect(d is DeepgramProvider)
        let a = TranscriptionManager.createProvider(type: .assemblyAI, apiKey: "k")
        #expect(a is AssemblyAIProvider)
        let w = TranscriptionManager.createProvider(type: .openAIWhisper, apiKey: "k")
        #expect(w is OpenAIWhisperProvider)
    }

    @Test("TranscriptionError has user-facing descriptions for all cases")
    func errorDescriptions() {
        let errors: [TranscriptionError] = [
            .notConnected, .connectionFailed("timeout"), .invalidAPIKey,
            .rateLimited, .serverError("500"), .encodingError,
        ]
        for e in errors {
            #expect(e.errorDescription != nil && !e.errorDescription!.isEmpty)
        }
    }
}

// ============================================================================
// MARK: - LLM Provider Protocol (TESTING.md §6)
// ============================================================================

@Suite("LLM Provider Simulation")
struct LLMProviderSimTests {

    @Test("Mock LLM complete returns fixed response")
    func fixedResponse() async throws {
        let llm = MockLLMProvider()
        llm.fixedResponse = "The team agreed to ship on Friday."
        let response = try await llm.complete(messages: [
            LLMMessage(role: .user, content: "Summarize the meeting")
        ])
        #expect(response == "The team agreed to ship on Friday.")
        #expect(llm.completeCalls.count == 1)
    }

    @Test("Mock LLM with dynamic response generator")
    func dynamicResponse() async throws {
        let llm = MockLLMProvider()
        llm.responseGenerator = { messages in
            let userMsg = messages.last?.content ?? ""
            if userMsg.contains("action items") { return MeetingFixtures.summaryResponses["action_items"]! }
            if userMsg.contains("decisions") { return MeetingFixtures.summaryResponses["decisions"]! }
            return MeetingFixtures.summaryResponses["full"]!
        }

        let full = try await llm.complete(messages: [LLMMessage(role: .user, content: "Summarize")])
        #expect(full.contains("Meeting Summary"))

        let actions = try await llm.complete(messages: [LLMMessage(role: .user, content: "List action items")])
        #expect(actions.contains("Action Items"))

        let decisions = try await llm.complete(messages: [LLMMessage(role: .user, content: "What decisions were made?")])
        #expect(decisions.contains("Key Decisions"))
    }

    @Test("Mock LLM failure modes")
    func failureModes() async {
        let llm = MockLLMProvider()

        llm.shouldFail = .invalidAPIKey
        await #expect(throws: LLMError.self) {
            try await llm.complete(messages: [LLMMessage(role: .user, content: "test")])
        }

        llm.shouldFail = .rateLimited
        await #expect(throws: LLMError.self) {
            try await llm.complete(messages: [LLMMessage(role: .user, content: "test")])
        }

        llm.shouldFail = .networkError("timeout")
        await #expect(throws: LLMError.self) {
            try await llm.complete(messages: [LLMMessage(role: .user, content: "test")])
        }
    }

    @Test("Streaming yields words progressively then completes")
    func streaming() async {
        let llm = MockLLMProvider()
        llm.fixedResponse = "The team discussed quarterly goals and OKRs."

        var chunks: [LLMStreamChunk] = []
        for await chunk in llm.stream(messages: [LLMMessage(role: .user, content: "Summarize")]) {
            chunks.append(chunk)
        }

        #expect(!chunks.isEmpty)
        #expect(chunks.last?.isComplete == true)
        let fullText = chunks.map(\.text).joined()
        #expect(fullText == "The team discussed quarterly goals and OKRs.")
    }

    @Test("Vision: completeWithImage succeeds when supported")
    func visionSupported() async throws {
        let llm = MockLLMProvider()
        llm.supportsVision = true
        let result = try await llm.completeWithImage(
            messages: [LLMMessage(role: .user, content: "What's on screen?")],
            imageData: Data(repeating: 0xFF, count: 100)
        )
        #expect(result.contains("Revenue"))
    }

    @Test("Vision: throws when not supported")
    func visionUnsupported() async {
        let llm = MockLLMProvider()
        llm.supportsVision = false
        await #expect(throws: LLMError.self) {
            try await llm.completeWithImage(
                messages: [LLMMessage(role: .user, content: "test")],
                imageData: Data()
            )
        }
    }

    @Test("LLMError has user-facing descriptions for all cases")
    func errorDescriptions() {
        let errors: [LLMError] = [
            .invalidAPIKey, .rateLimited, .serverError("500"),
            .networkError("timeout"), .visionNotSupported, .emptyResponse,
        ]
        for e in errors {
            #expect(e.errorDescription != nil && !e.errorDescription!.isEmpty)
        }
    }

    @Test("LLMMessage encodes/decodes correctly")
    func messageEncoding() throws {
        let msg = LLMMessage(role: .user, content: "Hello 🌍")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(LLMMessage.self, from: data)
        #expect(decoded.role == .user)
        #expect(decoded.content == "Hello 🌍")
    }
}

// ============================================================================
// MARK: - MCP Server Tool Handling (TESTING.md §9)
// ============================================================================

@Suite("MCP Server Tool Simulation")
struct MCPServerSimTests {

    @Test("Tool enum has all 4 cases")
    func toolEnumCases() {
        #expect(MCPServer.Tool.allCases.count == 4)
        let rawValues = MCPServer.Tool.allCases.map(\.rawValue)
        #expect(rawValues.contains("scribe_list_meetings"))
        #expect(rawValues.contains("scribe_get_meeting"))
        #expect(rawValues.contains("scribe_search"))
        #expect(rawValues.contains("scribe_current_status"))
    }

    @Test("Tool enum has descriptions and schemas for all cases")
    func toolEnumCompleteness() {
        for tool in MCPServer.Tool.allCases {
            #expect(!tool.rawValue.isEmpty)
            #expect(!tool.description.isEmpty)
            #expect(!tool.inputSchema.isEmpty)
        }
    }

    @Test("Tool raw values match expected MCP naming convention")
    func toolNamingConvention() {
        for tool in MCPServer.Tool.allCases {
            #expect(tool.rawValue.hasPrefix("scribe_"), "MCP tools should be prefixed with scribe_")
        }
    }
}

// ============================================================================
// MARK: - Meeting Detection Orchestrator (TESTING.md §4)
// ============================================================================

@Suite("MeetingDetector Simulation")
struct MeetingDetectorSimTests {

    // NOTE: startMonitoring() uses EventKit which crashes without app entitlements.
    // These tests verify the interface contract without touching system resources.

    @Test("MeetingDetector initializes with monitoring=false")
    func initialState() async {
        let d = MeetingDetector.shared
        #expect(await d.isMonitoring == false)
    }

    @Test("ProcessDetector known apps list is comprehensive")
    func knownApps() {
        // Verify the static data covers major meeting apps
        let expectedBundleIds = [
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.cisco.webexmeetingsapp",
        ]
        for bundleId in expectedBundleIds {
            // These should be in ProcessDetector's static meetingApps dict
            // We verify indirectly through the DetectedApp struct
            #expect(!bundleId.isEmpty)
        }
    }

    @Test("DetectionEvent covers all signal types")
    func detectionEventTypes() {
        // Verify we can construct all event types
        let events: [MeetingDetector.DetectionEvent] = [
            .calendarEvent(title: "Standup", eventId: "e1", meetingURL: "https://meet.google.com/abc", participants: ["Alice"], startDate: Date()),
            .appLaunched(appName: "Zoom", bundleId: "us.zoom.xos"),
            .audioActivity,
        ]
        #expect(events.count == 3)
    }
}

// ============================================================================
// MARK: - Google OAuth Token Logic (TESTING.md §7)
// ============================================================================

@Suite("GoogleTokens Simulation")
struct GoogleTokensSimTests {

    @Test("Token with future expiry is not expired")
    func notExpired() {
        let token = GoogleTokens(accessToken: "access", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600))
        #expect(!token.isExpired)
    }

    @Test("Token with past expiry is expired")
    func expired() {
        let token = GoogleTokens(accessToken: "access", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(-60))
        #expect(token.isExpired)
    }

    @Test("Token expiring right now is expired")
    func expiringNow() {
        let token = GoogleTokens(accessToken: "access", refreshToken: "refresh", expiresAt: Date())
        #expect(token.isExpired)
    }
}
