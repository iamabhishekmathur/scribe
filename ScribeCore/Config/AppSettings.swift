import Foundation
import SwiftUI

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
        static let summaryTypes = "summaryTypes"
        static let defaultTemplate = "defaultTemplate"
        static let meetingStoragePath = "meetingStoragePath"
        static let contentFont = "contentFont"
        static let appearance = "appearance"
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

    /// Which summary types to generate after a meeting. Defaults to all.
    @Published public var enabledSummaryTypes: Set<String> {
        didSet { defaults.set(Array(enabledSummaryTypes), forKey: Keys.summaryTypes) }
    }

    /// Default summary template for auto-summarization after recording stops
    @Published public var defaultTemplateId: String {
        didSet { defaults.set(defaultTemplateId, forKey: Keys.defaultTemplate) }
    }

    /// User-chosen folder for meeting markdown files. Nil = default ~/.scribe/meetings
    @Published public var meetingStoragePath: String {
        didSet { defaults.set(meetingStoragePath, forKey: Keys.meetingStoragePath) }
    }

    /// Font for meeting content (summary, notes, transcript). Default: "System Serif"
    @Published public var contentFont: String {
        didSet { defaults.set(contentFont, forKey: Keys.contentFont) }
    }

    /// Appearance mode: "system", "dark", "light"
    @Published public var appearance: String {
        didSet { defaults.set(appearance, forKey: Keys.appearance) }
    }

    /// Resolved URL for meeting storage folder
    public var meetingStorageURL: URL {
        if meetingStoragePath.isEmpty {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".scribe/meetings", isDirectory: true)
        }
        return URL(fileURLWithPath: meetingStoragePath, isDirectory: true)
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

        let savedTypes = defaults.stringArray(forKey: Keys.summaryTypes)
        self.enabledSummaryTypes = Set(savedTypes ?? ["full", "action_items", "decisions", "topics", "follow_ups"])
        self.defaultTemplateId = defaults.string(forKey: Keys.defaultTemplate) ?? "general"
        self.meetingStoragePath = defaults.string(forKey: Keys.meetingStoragePath) ?? ""
        self.contentFont = defaults.string(forKey: Keys.contentFont) ?? "System Serif"
        self.appearance = defaults.string(forKey: Keys.appearance) ?? "system"
    }
}

/// Font options for meeting content — all ship with macOS
public enum ContentFontOption: String, CaseIterable, Identifiable {
    case systemSerif = "System Serif"
    case systemSans = "System Sans"
    case systemMono = "System Mono"
    case georgia = "Georgia"
    case helveticaNeue = "Helvetica Neue"
    case avenirNext = "Avenir Next"
    case palatino = "Palatino"
    case charter = "Charter"
    case baskerville = "Baskerville"
    case optimaRegular = "Optima"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    /// Resolve to a SwiftUI Font for body text
    public func font(size: CGFloat = 14) -> Font {
        switch self {
        case .systemSerif: return .system(size: size, design: .serif)
        case .systemSans: return .system(size: size, design: .default)
        case .systemMono: return .system(size: size, design: .monospaced)
        default: return .custom(rawValue, size: size, relativeTo: .body)
        }
    }

    /// Resolve to a SwiftUI Font for headings
    public func headingFont(size: CGFloat = 17) -> Font {
        switch self {
        case .systemSerif: return .system(size: size, weight: .semibold, design: .serif)
        case .systemSans: return .system(size: size, weight: .semibold, design: .default)
        case .systemMono: return .system(size: size, weight: .semibold, design: .monospaced)
        default: return .custom(rawValue, size: size, relativeTo: .title3).weight(.semibold)
        }
    }

    public var isAvailable: Bool { true }
}
