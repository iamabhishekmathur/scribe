import Foundation

/// Stores API keys securely in an obfuscated file in Application Support.
/// For signed .app bundles, this could be swapped to use macOS Keychain.
/// Using file-based storage avoids Keychain password prompts for unsigned SPM executables.
@MainActor
public final class KeychainManager {
    public static let shared = KeychainManager()

    private var store: [String: String] = [:]
    private let storeURL: URL

    public enum Key: String, CaseIterable, Sendable {
        case deepgramAPIKey = "deepgram_api_key"
        case assemblyAIAPIKey = "assemblyai_api_key"
        case openAIAPIKey = "openai_api_key"
        case claudeAPIKey = "claude_api_key"
        case googleOAuthToken = "google_oauth_token"
        case googleOAuthRefreshToken = "google_oauth_refresh_token"
        case customLLMAPIKey = "custom_llm_api_key"

        public var displayName: String {
            switch self {
            case .deepgramAPIKey: return "Deepgram API Key"
            case .assemblyAIAPIKey: return "AssemblyAI API Key"
            case .openAIAPIKey: return "OpenAI API Key"
            case .claudeAPIKey: return "Claude API Key"
            case .googleOAuthToken: return "Google OAuth Token"
            case .googleOAuthRefreshToken: return "Google OAuth Refresh Token"
            case .customLLMAPIKey: return "Custom LLM API Key"
            }
        }
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Scribe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent(".credentials")
        load()
    }

    public func get(_ key: Key) -> String? {
        store[key.rawValue]
    }

    public func set(_ key: Key, value: String) throws {
        store[key.rawValue] = value
        save()
    }

    public func delete(_ key: Key) throws {
        store.removeValue(forKey: key.rawValue)
        save()
    }

    public func hasKey(_ key: Key) -> Bool {
        get(key) != nil
    }

    public func apiKeyForTranscriptionProvider(_ provider: TranscriptionProviderType) -> Key {
        switch provider {
        case .deepgram: return .deepgramAPIKey
        case .assemblyAI: return .assemblyAIAPIKey
        case .openAIWhisper: return .openAIAPIKey
        }
    }

    public func apiKeyForLLMProvider(_ provider: LLMProviderType) -> Key {
        switch provider {
        case .claude: return .claudeAPIKey
        case .openAI: return .openAIAPIKey
        case .ollama: return .customLLMAPIKey
        case .custom: return .customLLMAPIKey
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        // Simple XOR obfuscation (not encryption, but prevents casual reading)
        let decoded = deobfuscate(data)
        if let dict = try? JSONDecoder().decode([String: String].self, from: decoded) {
            store = dict
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        let encoded = obfuscate(data)
        try? encoded.write(to: storeURL)
        // Set file permissions to owner-only
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: storeURL.path
        )
    }

    private let obfuscationKey: [UInt8] = [0x5C, 0x72, 0x1B, 0xE3, 0xA9, 0x4F, 0x8D, 0x36]

    private func obfuscate(_ data: Data) -> Data {
        Data(data.enumerated().map { i, byte in
            byte ^ obfuscationKey[i % obfuscationKey.count]
        })
    }

    private func deobfuscate(_ data: Data) -> Data {
        obfuscate(data) // XOR is symmetric
    }
}
