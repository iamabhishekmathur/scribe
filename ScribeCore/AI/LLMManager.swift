import Foundation

/// Routes LLM requests to the active provider based on settings
@MainActor
public final class LLMManager {
    public static let shared = LLMManager()

    private var _provider: (any LLMProvider)?

    public var provider: any LLMProvider {
        if let p = _provider { return p }
        let p = createFromSettings()
        _provider = p
        return p
    }

    private init() {}

    /// Recreate provider from current settings (call after settings change)
    public func refresh() {
        _provider = createFromSettings()
    }

    private func createFromSettings() -> any LLMProvider {
        let settings = AppSettings.shared
        let keychain = KeychainManager.shared

        switch settings.llmProvider {
        case .claude:
            let key = keychain.get(.claudeAPIKey) ?? ""
            return ClaudeProvider(apiKey: key)
        case .openAI:
            let key = keychain.get(.openAIAPIKey) ?? ""
            return OpenAIProvider(apiKey: key)
        case .ollama:
            return OllamaProvider(model: settings.ollamaModel, endpoint: settings.ollamaEndpoint)
        case .custom:
            let key = keychain.get(.customLLMAPIKey) ?? ""
            return OpenAIProvider(
                apiKey: key,
                model: settings.customLLMModel,
                endpoint: settings.customLLMEndpoint
            )
        }
    }
}
