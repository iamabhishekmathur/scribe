import SwiftUI
import ScribeCore

public struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var permissions = PermissionsManager.shared

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }

            TranscriptionSettingsTab(settings: settings)
                .tabItem { Label("Transcription", systemImage: "text.bubble") }

            LLMSettingsTab(settings: settings)
                .tabItem { Label("AI / LLM", systemImage: "brain") }

            CalendarSettingsTab(settings: settings)
                .tabItem { Label("Calendar", systemImage: "calendar") }

            PermissionsSettingsTab(permissions: permissions)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 580, height: 500)
        .task {
            await permissions.checkAll()
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Meeting Detection") {
                Toggle("Auto-detect meetings", isOn: $settings.autoDetectMeetings)
                Toggle("Auto-start recording", isOn: $settings.autoStartRecording)
                Toggle("Show overlay during meetings", isOn: $settings.showOverlayDuringMeetings)
            }

            Section("Screen Context") {
                Toggle("Capture screen context during screen share", isOn: $settings.screenContextEnabled)
                if settings.screenContextEnabled {
                    LabeledContent("Capture interval") {
                        HStack {
                            TextField("", value: $settings.screenContextInterval, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                            Text("seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Transcription Settings

struct TranscriptionSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKeyInput: String = ""
    @State private var connectionStatus: ConnectionTestStatus = .idle
    @State private var keySaved = false

    enum ConnectionTestStatus {
        case idle, testing, success, failed(String)
    }

    var body: some View {
        Form {
            Section {
                Picker("Transcription Provider", selection: $settings.transcriptionProvider) {
                    ForEach(TranscriptionProviderType.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }

                Text(providerDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Provider")
            }

            Section {
                SecureField("Enter API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { loadKey() }
                    .onChange(of: settings.transcriptionProvider) { _ in
                        loadKey()
                        connectionStatus = .idle
                        keySaved = false
                    }

                HStack(spacing: 12) {
                    Button("Save Key") {
                        let keychainKey = KeychainManager.shared.apiKeyForTranscriptionProvider(settings.transcriptionProvider)
                        try? KeychainManager.shared.set(keychainKey, value: apiKeyInput)
                        keySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
                    }
                    .disabled(apiKeyInput.isEmpty)

                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(apiKeyInput.isEmpty)

                    Spacer()

                    statusIndicator
                }
            } header: {
                Text("API Key for \(settings.transcriptionProvider.rawValue)")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch connectionStatus {
        case .idle:
            if keySaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        case .testing:
            ProgressView().controlSize(.small)
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private var providerDescription: String {
        switch settings.transcriptionProvider {
        case .deepgram:
            return "Real-time streaming transcription with speaker diarization. Get a key at deepgram.com"
        case .assemblyAI:
            return "Real-time streaming transcription with base64 audio. Get a key at assemblyai.com"
        case .openAIWhisper:
            return "Chunked REST transcription (5s segments). Uses your OpenAI API key."
        }
    }

    private func loadKey() {
        let keychainKey = KeychainManager.shared.apiKeyForTranscriptionProvider(settings.transcriptionProvider)
        apiKeyInput = KeychainManager.shared.get(keychainKey) ?? ""
    }

    private func testConnection() {
        connectionStatus = .testing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if apiKeyInput.isEmpty {
                connectionStatus = .failed("No API key")
            } else {
                connectionStatus = .success
            }
        }
    }
}

// MARK: - LLM Settings

struct LLMSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKeyInput: String = ""
    @State private var keySaved = false
    @State private var validationError: String?

    var body: some View {
        Form {
            Section {
                Picker("LLM Provider", selection: $settings.llmProvider) {
                    ForEach(LLMProviderType.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }

                Text(providerDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Provider")
            }

            switch settings.llmProvider {
            case .claude, .openAI:
                Section {
                    SecureField("Enter API key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onAppear { loadKey() }
                        .onChange(of: settings.llmProvider) { _ in
                            loadKey()
                            validationError = nil
                            keySaved = false
                        }

                    if let error = validationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    HStack(spacing: 12) {
                        Button("Save & Validate") {
                            validateAndSaveKey()
                        }
                        .disabled(apiKeyInput.isEmpty)

                        Spacer()

                        if keySaved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("API Key for \(settings.llmProvider.rawValue)")
                }

            case .ollama:
                Section {
                    LabeledContent("Endpoint") {
                        TextField("http://localhost:11434", text: $settings.ollamaEndpoint)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model") {
                        TextField("llama3", text: $settings.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let error = validationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    Button("Test Connection") {
                        validateOllama()
                    }
                } header: {
                    Text("Ollama Configuration")
                }

            case .custom:
                Section {
                    LabeledContent("Endpoint URL") {
                        TextField("https://api.example.com/v1", text: $settings.customLLMEndpoint)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model name") {
                        TextField("gpt-4o", text: $settings.customLLMModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    SecureField("API Key (optional)", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            apiKeyInput = KeychainManager.shared.get(.customLLMAPIKey) ?? ""
                        }

                    if let error = validationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    HStack(spacing: 12) {
                        Button("Save & Validate") {
                            validateCustom()
                        }
                        .disabled(settings.customLLMEndpoint.isEmpty || settings.customLLMModel.isEmpty)

                        Spacer()

                        if keySaved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Custom Provider (OpenAI-compatible)")
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var providerDescription: String {
        switch settings.llmProvider {
        case .claude:
            return "Anthropic Claude for summaries, chat, and vision. Get a key at console.anthropic.com"
        case .openAI:
            return "OpenAI GPT models for summaries, chat, and vision. Get a key at platform.openai.com"
        case .ollama:
            return "Run models locally via Ollama. Free, no API key needed. Install from ollama.com"
        case .custom:
            return "Any OpenAI-compatible API endpoint (e.g., Azure OpenAI, Together, Groq)"
        }
    }

    private func loadKey() {
        let keychainKey = KeychainManager.shared.apiKeyForLLMProvider(settings.llmProvider)
        apiKeyInput = KeychainManager.shared.get(keychainKey) ?? ""
    }

    private func validateAndSaveKey() {
        validationError = nil
        keySaved = false

        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)

        // Basic format validation
        if key.isEmpty {
            validationError = "API key cannot be empty"
            return
        }

        switch settings.llmProvider {
        case .claude:
            if !key.hasPrefix("sk-ant-") {
                validationError = "Claude API keys start with 'sk-ant-'"
                return
            }
        case .openAI:
            if !key.hasPrefix("sk-") {
                validationError = "OpenAI API keys start with 'sk-'"
                return
            }
        default:
            break
        }

        if key.count < 20 {
            validationError = "API key seems too short"
            return
        }

        // Save to keychain
        let keychainKey = KeychainManager.shared.apiKeyForLLMProvider(settings.llmProvider)
        try? KeychainManager.shared.set(keychainKey, value: key)
        LLMManager.shared.refresh()
        keySaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { keySaved = false }
    }

    private func validateOllama() {
        validationError = nil
        let endpoint = settings.ollamaEndpoint.trimmingCharacters(in: .whitespaces)

        if endpoint.isEmpty {
            validationError = "Endpoint URL is required"
            return
        }
        if !endpoint.hasPrefix("http") {
            validationError = "Endpoint must start with http:// or https://"
            return
        }
        if settings.ollamaModel.trimmingCharacters(in: .whitespaces).isEmpty {
            validationError = "Model name is required"
            return
        }

        // Test actual connection
        Task {
            do {
                let url = URL(string: "\(endpoint)/api/tags")!
                let (_, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    await MainActor.run {
                        keySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { keySaved = false }
                    }
                } else {
                    await MainActor.run { validationError = "Ollama not responding" }
                }
            } catch {
                await MainActor.run { validationError = "Cannot reach Ollama at \(endpoint)" }
            }
        }
    }

    private func validateCustom() {
        validationError = nil
        let endpoint = settings.customLLMEndpoint.trimmingCharacters(in: .whitespaces)

        if endpoint.isEmpty {
            validationError = "Endpoint URL is required"
            return
        }
        if !endpoint.hasPrefix("http") {
            validationError = "Endpoint must start with http:// or https://"
            return
        }
        if settings.customLLMModel.trimmingCharacters(in: .whitespaces).isEmpty {
            validationError = "Model name is required"
            return
        }

        try? KeychainManager.shared.set(.customLLMAPIKey, value: apiKeyInput)
        LLMManager.shared.refresh()
        keySaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { keySaved = false }
    }
}

// MARK: - Calendar Settings

struct CalendarSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var googleClientId: String = ""
    @State private var isGoogleConnected = false
    @State private var googleStatus: String = ""
    @State private var isConnecting = false

    var body: some View {
        Form {
            Section {
                Toggle("Use Apple Calendar (EventKit)", isOn: .constant(true))
                    .disabled(true)
                Text("Automatically reads events from calendars configured in macOS Calendar app. No setup needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Apple Calendar")
            } footer: {
                Text("Supports iCloud, Google, Exchange, and other accounts added in System Settings > Internet Accounts.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section {
                HStack {
                    Image(systemName: isGoogleConnected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isGoogleConnected ? .green : .secondary)
                    Text(isGoogleConnected ? "Connected" : "Not connected")
                        .foregroundStyle(isGoogleConnected ? .primary : .secondary)
                }

                if !isGoogleConnected {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To connect Google Calendar directly (without adding to macOS Calendar):")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LabeledContent("OAuth Client ID") {
                            TextField("your-client-id.apps.googleusercontent.com", text: $googleClientId)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("Create OAuth credentials at console.cloud.google.com > APIs & Services > Credentials. Use 'Desktop app' type.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 12) {
                            Button("Connect Google Calendar") {
                                connectGoogle()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(googleClientId.isEmpty || isConnecting)

                            if isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                } else {
                    Button("Disconnect") {
                        disconnectGoogle()
                    }
                    .foregroundStyle(.red)
                }

                if !googleStatus.isEmpty {
                    Text(googleStatus)
                        .font(.caption)
                        .foregroundStyle(googleStatus.contains("Error") ? .red : .green)
                }
            } header: {
                Text("Google Calendar (Direct API)")
            } footer: {
                Text("Use this if you don't want to add your Google account to macOS Calendar. Requires a Google Cloud OAuth client ID.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section {
                Text("Outlook / Microsoft 365 calendar support is planned for a future release.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("Outlook Calendar")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onAppear {
            googleClientId = UserDefaults.standard.string(forKey: "googleOAuthClientId") ?? ""
            isGoogleConnected = KeychainManager.shared.hasKey(.googleOAuthToken)
        }
    }

    private func connectGoogle() {
        guard !googleClientId.isEmpty else { return }
        isConnecting = true
        googleStatus = ""

        // Save the client ID
        UserDefaults.standard.set(googleClientId, forKey: "googleOAuthClientId")

        Task {
            do {
                let tokens = try await GoogleOAuthManager.shared.authorize()
                try? KeychainManager.shared.set(.googleOAuthToken, value: tokens.accessToken)
                if let refresh = tokens.refreshToken {
                    try? KeychainManager.shared.set(.googleOAuthRefreshToken, value: refresh)
                }
                await CalendarManager.shared.setGoogleToken(tokens.accessToken)
                await MainActor.run {
                    isGoogleConnected = true
                    isConnecting = false
                    googleStatus = "Connected successfully"
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    googleStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func disconnectGoogle() {
        try? KeychainManager.shared.delete(.googleOAuthToken)
        try? KeychainManager.shared.delete(.googleOAuthRefreshToken)
        isGoogleConnected = false
        googleStatus = ""
    }
}

// MARK: - Permissions Settings

struct PermissionsSettingsTab: View {
    @ObservedObject var permissions: PermissionsManager

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    name: "Microphone",
                    icon: "mic.fill",
                    description: "Capture your voice during meetings",
                    granted: permissions.microphoneGranted,
                    action: { Task { await permissions.checkMicrophone() } }
                )

                PermissionRow(
                    name: "Screen Recording",
                    icon: "rectangle.dashed.badge.record",
                    description: "Capture system audio from meeting apps",
                    granted: permissions.screenRecordingGranted,
                    action: { Task { await permissions.checkScreenRecording() } }
                )

                PermissionRow(
                    name: "Calendar",
                    icon: "calendar",
                    description: "Detect upcoming meetings automatically",
                    granted: permissions.calendarGranted,
                    action: { Task { await permissions.checkCalendar() } }
                )

                PermissionRow(
                    name: "Notifications",
                    icon: "bell.fill",
                    description: permissions.hasBundleId
                        ? "Alert you when meetings are detected"
                        : "Not available in dev mode — requires packaged .app",
                    granted: permissions.notificationsGranted,
                    action: {
                        if permissions.hasBundleId {
                            Task { await permissions.checkNotifications() }
                        } else {
                            permissions.openNotificationSettings()
                        }
                    }
                )
            } header: {
                Text("Required Permissions")
            } footer: {
                Text("Some permissions require restarting Scribe after granting.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section {
                Button("Open System Settings") {
                    permissions.openSystemPreferences()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct PermissionRow: View {
    let name: String
    let icon: String
    let description: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(granted ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Button("Request") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
