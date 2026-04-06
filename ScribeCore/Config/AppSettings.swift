import Foundation

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let transcriptionProvider = "transcriptionProvider"
        static let llmProvider = "llmProvider"
        static let ollamaModel = "ollamaModel"
        static let ollamaEndpoint = "ollamaEndpoint"
        static let customLLMEndpoint = "customLLMEndpoint"
        static let customLLMModel = "customLLMModel"
        static let autoDetectMeetings = "autoDetectMeetings"
        static let showOverlayDuringMeetings = "showOverlayDuringMeetings"
        static let autoStartRecording = "autoStartRecording"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let screenContextEnabled = "screenContextEnabled"
        static let screenContextInterval = "screenContextInterval"
    }

    @Published public var transcriptionProvider: TranscriptionProviderType {
        didSet { defaults.set(transcriptionProvider.rawValue, forKey: Keys.transcriptionProvider) }
    }

    @Published public var llmProvider: LLMProviderType {
        didSet { defaults.set(llmProvider.rawValue, forKey: Keys.llmProvider) }
    }

    @Published public var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Keys.ollamaModel) }
    }

    @Published public var ollamaEndpoint: String {
        didSet { defaults.set(ollamaEndpoint, forKey: Keys.ollamaEndpoint) }
    }

    @Published public var customLLMEndpoint: String {
        didSet { defaults.set(customLLMEndpoint, forKey: Keys.customLLMEndpoint) }
    }

    @Published public var customLLMModel: String {
        didSet { defaults.set(customLLMModel, forKey: Keys.customLLMModel) }
    }

    @Published public var autoDetectMeetings: Bool {
        didSet { defaults.set(autoDetectMeetings, forKey: Keys.autoDetectMeetings) }
    }

    @Published public var showOverlayDuringMeetings: Bool {
        didSet { defaults.set(showOverlayDuringMeetings, forKey: Keys.showOverlayDuringMeetings) }
    }

    @Published public var autoStartRecording: Bool {
        didSet { defaults.set(autoStartRecording, forKey: Keys.autoStartRecording) }
    }

    @Published public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    @Published public var screenContextEnabled: Bool {
        didSet { defaults.set(screenContextEnabled, forKey: Keys.screenContextEnabled) }
    }

    @Published public var screenContextInterval: Double {
        didSet { defaults.set(screenContextInterval, forKey: Keys.screenContextInterval) }
    }

    private init() {
        let provider = defaults.string(forKey: Keys.transcriptionProvider) ?? TranscriptionProviderType.deepgram.rawValue
        self.transcriptionProvider = TranscriptionProviderType(rawValue: provider) ?? .deepgram

        let llm = defaults.string(forKey: Keys.llmProvider) ?? LLMProviderType.claude.rawValue
        self.llmProvider = LLMProviderType(rawValue: llm) ?? .claude

        self.ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "llama3"
        self.ollamaEndpoint = defaults.string(forKey: Keys.ollamaEndpoint) ?? "http://localhost:11434"
        self.customLLMEndpoint = defaults.string(forKey: Keys.customLLMEndpoint) ?? ""
        self.customLLMModel = defaults.string(forKey: Keys.customLLMModel) ?? ""

        self.autoDetectMeetings = defaults.object(forKey: Keys.autoDetectMeetings) as? Bool ?? true
        self.showOverlayDuringMeetings = defaults.object(forKey: Keys.showOverlayDuringMeetings) as? Bool ?? true
        self.autoStartRecording = defaults.object(forKey: Keys.autoStartRecording) as? Bool ?? false
        self.hasCompletedOnboarding = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? false
        self.screenContextEnabled = defaults.object(forKey: Keys.screenContextEnabled) as? Bool ?? true
        self.screenContextInterval = defaults.object(forKey: Keys.screenContextInterval) as? Double ?? 15.0
    }
}
