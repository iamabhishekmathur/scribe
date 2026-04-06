import Foundation
@testable import ScribeCore

// ============================================================================
// MARK: - Mock LLM Provider
// ============================================================================

/// Simulates an LLM provider. Returns canned responses, tracks all calls.
final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    var completeCalls: [(messages: [LLMMessage], response: String)] = []
    var shouldFail: LLMError?
    var responseDelay: Duration = .zero
    var supportsVision: Bool = true

    /// Fixed response for complete()
    var fixedResponse: String = "This is a mock LLM response."
    /// Dynamic response generator
    var responseGenerator: (([LLMMessage]) -> String)?

    func complete(messages: [LLMMessage]) async throws -> String {
        if let err = shouldFail { throw err }
        if responseDelay > .zero { try? await Task.sleep(for: responseDelay) }
        let response = responseGenerator?(messages) ?? fixedResponse
        completeCalls.append((messages: messages, response: response))
        return response
    }

    func stream(messages: [LLMMessage]) -> AsyncStream<LLMStreamChunk> {
        AsyncStream { continuation in
            let response = self.responseGenerator?(messages) ?? self.fixedResponse
            // Simulate streaming word-by-word
            let words = response.split(separator: " ")
            for (i, word) in words.enumerated() {
                let isLast = i == words.count - 1
                continuation.yield(LLMStreamChunk(text: String(word) + (isLast ? "" : " "), isComplete: isLast))
            }
            continuation.finish()
        }
    }

    func completeWithImage(messages: [LLMMessage], imageData: Data) async throws -> String {
        if !supportsVision { throw LLMError.visionNotSupported }
        if let err = shouldFail { throw err }
        return "Extracted text from image: Revenue Q1 $12.5M"
    }
}

// ============================================================================
// MARK: - Mock Transcription Provider
// ============================================================================

/// Simulates a transcription provider. Emits pre-configured results.
final class MockTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    var isConnected: Bool = false
    let results: AsyncStream<TranscriptionResult>
    private let resultsContinuation: AsyncStream<TranscriptionResult>.Continuation

    var connectCalled = false
    var disconnectCalled = false
    var audioChunksReceived = 0
    var shouldFailOnConnect = false
    var failError: TranscriptionError = .invalidAPIKey

    init() {
        var cont: AsyncStream<TranscriptionResult>.Continuation!
        self.results = AsyncStream { cont = $0 }
        self.resultsContinuation = cont
    }

    func connect() async throws {
        connectCalled = true
        if shouldFailOnConnect { throw failError }
        isConnected = true
    }

    func sendAudio(_ data: Data) async throws {
        guard isConnected else { throw TranscriptionError.notConnected }
        audioChunksReceived += 1
    }

    func disconnect() async {
        disconnectCalled = true
        isConnected = false
        resultsContinuation.finish()
    }

    func emit(_ result: TranscriptionResult) {
        resultsContinuation.yield(result)
    }

    func emitAll(_ segments: [SimulatedSegment]) {
        for seg in segments {
            resultsContinuation.yield(seg.toResult())
        }
        resultsContinuation.finish()
    }
}

// ============================================================================
// MARK: - Simulated Segment
// ============================================================================

struct SimulatedSegment: Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let speaker: String?
    let speakerIndex: Int?
    let confidence: Double?
    let isFinal: Bool

    init(_ text: String, start: TimeInterval, end: TimeInterval,
         speaker: String? = nil, speakerIdx: Int? = nil,
         confidence: Double? = 0.95, isFinal: Bool = true) {
        self.text = text; self.startTime = start; self.endTime = end
        self.speaker = speaker; self.speakerIndex = speakerIdx
        self.confidence = confidence; self.isFinal = isFinal
    }

    func toResult() -> TranscriptionResult {
        TranscriptionResult(text: text, startTime: startTime, endTime: endTime,
                            speaker: speaker, speakerIndex: speakerIndex,
                            confidence: confidence, isFinal: isFinal)
    }

    func toSegment(meetingId: UUID) -> TranscriptSegment {
        TranscriptSegment(meetingId: meetingId, speaker: speaker, speakerIndex: speakerIndex,
                          text: text, startTime: startTime, endTime: endTime,
                          confidence: confidence, isFinal: isFinal)
    }
}

// ============================================================================
// MARK: - Meeting Data Generators
// ============================================================================

/// Generates realistic meeting fixtures per agentic-qa-skill Phase 4
enum MeetingFixtures {

    // MARK: - Meeting Types

    /// 5-min standup, 3 speakers, action items
    static let standup: [SimulatedSegment] = [
        .init("Alright, let's get started with standup.", start: 0, end: 3, speaker: "Speaker 0", speakerIdx: 0),
        .init("Yesterday I finished the authentication module and opened a PR.", start: 3, end: 8, speaker: "Speaker 1", speakerIdx: 1),
        .init("Today I'm working on the dashboard API endpoints.", start: 8, end: 12, speaker: "Speaker 1", speakerIdx: 1),
        .init("No blockers for me.", start: 12, end: 14, speaker: "Speaker 1", speakerIdx: 1),
        .init("Great. Alice, you're up.", start: 14, end: 16, speaker: "Speaker 0", speakerIdx: 0),
        .init("I've been debugging the payment integration issue.", start: 16, end: 21, speaker: "Speaker 2", speakerIdx: 2),
        .init("The webhook URL was misconfigured in staging.", start: 21, end: 26, speaker: "Speaker 2", speakerIdx: 2),
        .init("I fixed it, tests are passing now.", start: 26, end: 30, speaker: "Speaker 2", speakerIdx: 2),
        .init("Today I'll deploy the fix to production.", start: 30, end: 34, speaker: "Speaker 2", speakerIdx: 2),
        .init("Blocker: I need someone to review my PR.", start: 34, end: 39, speaker: "Speaker 2", speakerIdx: 2),
        .init("I can review it after this call.", start: 39, end: 42, speaker: "Speaker 1", speakerIdx: 1),
        .init("Perfect. I worked on the database migration scripts yesterday.", start: 42, end: 48, speaker: "Speaker 0", speakerIdx: 0),
        .init("We need to schedule downtime for the migration.", start: 48, end: 53, speaker: "Speaker 0", speakerIdx: 0),
        .init("Let's do that Thursday evening after hours.", start: 53, end: 57, speaker: "Speaker 0", speakerIdx: 0),
        .init("Sounds good. Have a great day everyone.", start: 57, end: 62, speaker: "Speaker 0", speakerIdx: 0),
    ]

    /// Interim results (progressive refinement from streaming provider)
    static let interimStream: [SimulatedSegment] = [
        .init("Let's", start: 0, end: 0.5, isFinal: false),
        .init("Let's get", start: 0, end: 1.0, isFinal: false),
        .init("Let's get started", start: 0, end: 1.5, isFinal: false),
        .init("Let's get started with the meeting.", start: 0, end: 3, confidence: 0.97, isFinal: true),
    ]

    /// Overlapping speakers (rapid crosstalk)
    static let crosstalk: [SimulatedSegment] = [
        .init("I disagree.", start: 0, end: 1, speaker: "Speaker 0", speakerIdx: 0),
        .init("But the data shows—", start: 0.8, end: 2.5, speaker: "Speaker 1", speakerIdx: 1),
        .init("We've tried that before.", start: 2, end: 3.5, speaker: "Speaker 2", speakerIdx: 2),
        .init("Let me finish.", start: 3, end: 4, speaker: "Speaker 1", speakerIdx: 1),
        .init("Sorry, go ahead.", start: 3.8, end: 5, speaker: "Speaker 0", speakerIdx: 0),
    ]

    /// Multilingual content (CJK, Arabic, accented Latin)
    static let multilingual: [SimulatedSegment] = [
        .init("Let's review the Q1 results for the 東京 office.", start: 0, end: 5, speaker: "Speaker 0", speakerIdx: 0),
        .init("收入增长了百分之十五。", start: 5, end: 10, speaker: "Speaker 1", speakerIdx: 1),
        .init("The München team also hit their targets.", start: 10, end: 15, speaker: "Speaker 0", speakerIdx: 0),
        .init("نعم، الأرقام ممتازة هذا الربع.", start: 15, end: 20, speaker: "Speaker 2", speakerIdx: 2),
        .init("Très bien! Let's move to São Paulo numbers.", start: 20, end: 25, speaker: "Speaker 0", speakerIdx: 0),
    ]

    /// Presentation with screen context captures
    static let screenContexts: [ScreenContext] = {
        let id = UUID()
        return [
            ScreenContext(meetingId: id, timestamp: 30, extractedText: "Q1 Revenue: $12.5M\nGrowth: +15% YoY", sourceDescription: "Google Slides"),
            ScreenContext(meetingId: id, timestamp: 45, extractedText: "Customer Acquisition Cost: $45\nDown 30% from Q4", sourceDescription: "Google Slides"),
            ScreenContext(meetingId: id, timestamp: 60, extractedText: "NPS Score: 68 (up from 42)\nTarget: 70 by Q3", sourceDescription: "Google Slides"),
            ScreenContext(meetingId: id, timestamp: 90, extractedText: "Strategic Initiatives:\n1. International Expansion\n2. Enterprise Tier\n3. API Platform", sourceDescription: "Google Slides"),
        ]
    }()

    // MARK: - Scale Data

    /// Generate N transcript segments for a meeting
    private static let prefixes = ["We should focus on", "The key issue is", "I think we need to", "Let me share my thoughts on", "Looking at the data,"]
    private static let suffixes = ["the quarterly targets.", "customer retention.", "the new feature rollout.", "our hiring plan.", "the infrastructure migration."]

    static func generateSegments(count: Int, meetingId: UUID, speakers: Int = 3) -> [TranscriptSegment] {
        (0..<count).map { i in
            let text = "Segment \(i): " + prefixes[i % 5] + " " + suffixes[i % 5]
            return TranscriptSegment(
                meetingId: meetingId,
                speaker: "Speaker \(i % speakers)",
                speakerIndex: i % speakers,
                text: text,
                startTime: Double(i) * 3.0,
                endTime: Double(i) * 3.0 + 2.5,
                confidence: Double.random(in: 0.7...0.99)
            )
        }
    }

    /// Generate a complete meeting with all related data
    static func completeMeeting(
        title: String = "Sprint Planning",
        segmentCount: Int = 15,
        noteCount: Int = 2,
        summaryTypes: [String] = ["full", "action_items", "decisions"]
    ) -> (meeting: MeetingRecord, segments: [TranscriptSegment], notes: [UserNote], summaries: [AISummary], contexts: [ScreenContext]) {
        let id = UUID()
        let meeting = MeetingRecord(id: id, title: title, endTime: Date(), duration: 3600, state: "complete")
        let segments = generateSegments(count: segmentCount, meetingId: id)
        let notes = (0..<noteCount).map { i in
            UserNote(meetingId: id, text: "Action item \(i + 1): Follow up on discussion point", timestamp: Double(i * 30 + 15))
        }
        let summaries = summaryTypes.map { type in
            AISummary(meetingId: id, summaryType: type, content: "Mock \(type) summary for \(title). Key points discussed include project updates and action items.", modelUsed: "mock-model")
        }
        let contexts = [
            ScreenContext(meetingId: id, timestamp: 30, extractedText: "Slide: Project Timeline Q2 2026"),
            ScreenContext(meetingId: id, timestamp: 60, extractedText: "Slide: Budget Allocation"),
        ]
        return (meeting, segments, notes, summaries, contexts)
    }

    // MARK: - Summary Responses (for MockLLMProvider)

    static let summaryResponses: [String: String] = [
        "full": """
        ## Meeting Summary
        The team discussed progress on the authentication module, payment integration bug fix, and upcoming database migration. Key decisions were made about scheduling downtime and PR review assignments.
        """,
        "action_items": """
        ## Action Items
        1. Bob: Review Alice's payment integration PR (today)
        2. Alice: Deploy payment fix to production (today)
        3. Team: Schedule Thursday evening downtime for DB migration
        """,
        "decisions": """
        ## Key Decisions
        - Database migration scheduled for Thursday evening after hours
        - Bob will handle Alice's PR review after standup
        - Payment fix cleared for production deployment
        """,
    ]
}

// ============================================================================
// MARK: - URL Extraction Patterns (for testing CalendarDetector logic)
// ============================================================================

enum MeetingURLTestCases {
    static let valid: [(input: String, expectedDomain: String)] = [
        ("Join at https://meet.google.com/abc-def-ghi", "meet.google.com"),
        ("Zoom: https://company.zoom.us/j/1234567890", "zoom.us"),
        ("https://teams.microsoft.com/l/meetup-join/abc123", "teams.microsoft.com"),
        ("https://company.webex.com/meet/john.doe", "webex.com"),
    ]

    static let noURL: [String] = [
        "Lunch with Bob",
        "Doctor appointment",
        "Flight AA123 SFO->JFK",
        "",
    ]

    static let embeddedURLs: [(input: String, shouldFind: Bool)] = [
        ("Meeting notes: https://meet.google.com/xyz-abc-def please join", true),
        ("Location: Building 42, Room 3A", false),
        ("Zoom link in calendar: https://us02web.zoom.us/j/85123456789?pwd=abc", true),
        ("Call me at 555-1234", false),
    ]
}
