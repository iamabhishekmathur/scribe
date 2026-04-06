import Foundation
import Combine

public enum RecordingState: String {
    case idle
    case recording
    case processing
}

public enum TranscriptionProviderType: String, CaseIterable, Identifiable {
    case deepgram = "Deepgram"
    case assemblyAI = "AssemblyAI"
    case openAIWhisper = "OpenAI Whisper"

    public var id: String { rawValue }
}

public enum LLMProviderType: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case openAI = "OpenAI"
    case ollama = "Ollama"
    case custom = "Custom (OpenAI-compatible)"

    public var id: String { rawValue }
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var recordingState: RecordingState = .idle
    @Published public var currentMeetingId: UUID?
    @Published public var audioLevel: Float = 0.0
    @Published public var isOverlayVisible: Bool = false

    public init() {}

    public func startRecording(meetingId: UUID) {
        self.currentMeetingId = meetingId
        self.recordingState = .recording
    }

    public func stopRecording() {
        self.recordingState = .processing
    }

    public func finishProcessing() {
        self.recordingState = .idle
        self.currentMeetingId = nil
    }
}
