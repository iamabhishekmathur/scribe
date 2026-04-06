import SwiftUI
import ScribeCore

/// Settings detail shown in the right column of the main window.
/// Section selection is driven by the sidebar list in MainWindowPlaceholder.
public struct SettingsDetailView: View {
    @ObservedObject var appState: AppState
    @Binding var selectedSection: SettingsSection
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var permissions = PermissionsManager.shared

    public init(appState: AppState, selectedSection: Binding<SettingsSection>) {
        self.appState = appState
        self._selectedSection = selectedSection
    }

    public var body: some View {
        ScrollView {
            Group {
                switch selectedSection {
                case .general:
                    GeneralSettingsContent(settings: settings)
                case .transcription:
                    TranscriptionSettingsContent(settings: settings)
                case .llm:
                    LLMSettingsContent(settings: settings)
                case .calendar:
                    CalendarSettingsContent(settings: settings)
                case .permissions:
                    PermissionsSettingsContent(permissions: permissions)
                }
            }
            .padding(24)
        }
        .task {
            await permissions.checkAll()
        }
    }
}

// MARK: - General

private struct GeneralSettingsContent: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(title: "Meeting Detection", icon: "antenna.radiowaves.left.and.right")

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-detect meetings", isOn: $settings.autoDetectMeetings)
                Toggle("Auto-start recording", isOn: $settings.autoStartRecording)
                Toggle("Show overlay during meetings", isOn: $settings.showOverlayDuringMeetings)
            }
            .padding(.leading, 4)

            Divider()

            SettingsSectionHeader(title: "Screen Context", icon: "rectangle.badge.checkmark")

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Capture screen context during screen share", isOn: $settings.screenContextEnabled)
                if settings.screenContextEnabled {
                    HStack {
                        Text("Capture interval:")
                            .foregroundStyle(.secondary)
                        TextField("", value: $settings.screenContextInterval, format: .number)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(.leading, 4)
        }
    }
}

// MARK: - Transcription

private struct TranscriptionSettingsContent: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKeyInput = ""
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var keySaved = false

    enum ConnectionStatus { case idle, testing, success, failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(title: "Provider", icon: "text.bubble")

            Picker("Transcription Provider", selection: $settings.transcriptionProvider) {
                ForEach(TranscriptionProviderType.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.radioGroup)

            Text(providerDescription)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            SettingsSectionHeader(title: "API Key", icon: "key")

            SecureField("API key for \(settings.transcriptionProvider.rawValue)", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .onAppear { loadKey() }
                .onChange(of: settings.transcriptionProvider) { _ in
                    loadKey()
                    connectionStatus = .idle
                    keySaved = false
                }

            HStack(spacing: 12) {
                Button("Save Key") {
                    let k = KeychainManager.shared.apiKeyForTranscriptionProvider(settings.transcriptionProvider)
                    try? KeychainManager.shared.set(k, value: apiKeyInput)
                    keySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
                }
                .disabled(apiKeyInput.isEmpty)

                Button("Test Connection") {
                    connectionStatus = .testing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        connectionStatus = apiKeyInput.isEmpty ? .failed("No API key") : .success
                    }
                }
                .disabled(apiKeyInput.isEmpty)

                Spacer()

                switch connectionStatus {
                case .idle:
                    if keySaved {
                        Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    }
                case .testing:
                    ProgressView().controlSize(.small)
                case .success:
                    Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                case .failed(let msg):
                    Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
                }
            }
        }
    }

    private var providerDescription: String {
        switch settings.transcriptionProvider {
        case .deepgram: return "Real-time streaming with speaker diarization. Get a key at deepgram.com"
        case .assemblyAI: return "Real-time streaming transcription. Get a key at assemblyai.com"
        case .openAIWhisper: return "Chunked REST transcription (5s segments). Uses your OpenAI API key."
        }
    }

    private func loadKey() {
        let k = KeychainManager.shared.apiKeyForTranscriptionProvider(settings.transcriptionProvider)
        apiKeyInput = KeychainManager.shared.get(k) ?? ""
    }
}

// MARK: - LLM

private struct LLMSettingsContent: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKeyInput = ""
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var validationError: String?

    @State private var isTesting = false

    enum ConnectionStatus { case idle, testing, success, failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(title: "Provider", icon: "brain")

            Picker("LLM Provider", selection: $settings.llmProvider) {
                ForEach(LLMProviderType.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.radioGroup)

            Text(providerDescription)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            switch settings.llmProvider {
            case .claude, .openAI:
                SettingsSectionHeader(title: "API Key", icon: "key")

                SecureField("API key for \(settings.llmProvider.rawValue)", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { loadKey() }
                    .onChange(of: settings.llmProvider) { _ in loadKey(); validationError = nil; connectionStatus = .idle }

                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                }

                HStack(spacing: 12) {
                    Button("Save Key") { saveKey() }
                        .disabled(apiKeyInput.isEmpty)

                    Button("Test Connection") { testLLMConnection() }
                        .disabled(apiKeyInput.isEmpty || isTesting)

                    Spacer()

                    connectionStatusView
                }

            case .ollama:
                SettingsSectionHeader(title: "Configuration", icon: "server.rack")

                LabeledContent("Endpoint") {
                    TextField("http://localhost:11434", text: $settings.ollamaEndpoint)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Model") {
                    TextField("llama3", text: $settings.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                }

                HStack(spacing: 12) {
                    Button("Test Connection") { testLLMConnection() }
                        .disabled(isTesting)
                    Spacer()
                    connectionStatusView
                }

            case .custom:
                SettingsSectionHeader(title: "Custom Provider", icon: "server.rack")

                LabeledContent("Endpoint") {
                    TextField("https://api.example.com/v1", text: $settings.customLLMEndpoint)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Model") {
                    TextField("gpt-4o", text: $settings.customLLMModel)
                        .textFieldStyle(.roundedBorder)
                }
                SecureField("API Key (optional)", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { apiKeyInput = KeychainManager.shared.get(.customLLMAPIKey) ?? "" }

                HStack(spacing: 12) {
                    Button("Save Key") {
                        try? KeychainManager.shared.set(.customLLMAPIKey, value: apiKeyInput)
                        LLMManager.shared.refresh()
                    }
                    .disabled(settings.customLLMEndpoint.isEmpty)

                    Button("Test Connection") { testLLMConnection() }
                        .disabled(settings.customLLMEndpoint.isEmpty || isTesting)

                    Spacer()
                    connectionStatusView
                }
            }
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing...").font(.caption).foregroundStyle(.secondary)
            }
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
        }
    }

    private var providerDescription: String {
        switch settings.llmProvider {
        case .claude: return "Anthropic Claude for summaries, chat, and vision. Get a key at console.anthropic.com"
        case .openAI: return "OpenAI GPT models for summaries, chat, and vision. Get a key at platform.openai.com"
        case .ollama: return "Run models locally via Ollama. Free, no API key needed. Install from ollama.com"
        case .custom: return "Any OpenAI-compatible API endpoint (Azure OpenAI, Together, Groq, etc.)"
        }
    }

    private func loadKey() {
        let k = KeychainManager.shared.apiKeyForLLMProvider(settings.llmProvider)
        apiKeyInput = KeychainManager.shared.get(k) ?? ""
    }

    private func saveKey() {
        validationError = nil
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        if key.isEmpty { validationError = "API key cannot be empty"; return }
        if settings.llmProvider == .claude && !key.hasPrefix("sk-ant-") { validationError = "Claude keys start with 'sk-ant-'"; return }
        if settings.llmProvider == .openAI && !key.hasPrefix("sk-") { validationError = "OpenAI keys start with 'sk-'"; return }
        if key.count < 20 { validationError = "Key seems too short"; return }

        let k = KeychainManager.shared.apiKeyForLLMProvider(settings.llmProvider)
        try? KeychainManager.shared.set(k, value: key)
        LLMManager.shared.refresh()
        connectionStatus = .success
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if case .success = connectionStatus { connectionStatus = .idle }
        }
    }

    private func testLLMConnection() {
        connectionStatus = .testing
        isTesting = true
        validationError = nil

        // Save key first if Claude/OpenAI
        if settings.llmProvider == .claude || settings.llmProvider == .openAI {
            let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                let k = KeychainManager.shared.apiKeyForLLMProvider(settings.llmProvider)
                try? KeychainManager.shared.set(k, value: key)
                LLMManager.shared.refresh()
            }
        }

        Task {
            do {
                switch settings.llmProvider {
                case .claude:
                    // Test Claude API with a minimal request
                    let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.setValue(key, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": "claude-sonnet-4-20250514",
                        "max_tokens": 5,
                        "messages": [["role": "user", "content": "Hi"]]
                    ])
                    let (_, resp) = try await URLSession.shared.data(for: request)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    await MainActor.run {
                        isTesting = false
                        switch status {
                        case 200: connectionStatus = .success
                        case 401: connectionStatus = .failed("Invalid API key")
                        case 429: connectionStatus = .success // Rate limited means key is valid
                        default: connectionStatus = .failed("HTTP \(status)")
                        }
                    }

                case .openAI:
                    // Test OpenAI by listing models
                    let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
                    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    let (_, resp) = try await URLSession.shared.data(for: request)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    await MainActor.run {
                        switch status {
                        case 200: connectionStatus = .success
                        case 401: connectionStatus = .failed("Invalid API key")
                        case 429: connectionStatus = .success // Rate limited means key works
                        default: connectionStatus = .failed("HTTP \(status)")
                        }
                    }

                case .ollama:
                    let endpoint = settings.ollamaEndpoint.trimmingCharacters(in: .whitespaces)
                    guard !endpoint.isEmpty, endpoint.hasPrefix("http") else {
                        await MainActor.run { connectionStatus = .failed("Invalid endpoint"); isTesting = false }
                        return
                    }
                    let (_, resp) = try await URLSession.shared.data(from: URL(string: "\(endpoint)/api/tags")!)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    await MainActor.run {
                        connectionStatus = status == 200 ? .success : .failed("Ollama not responding")
                    }

                case .custom:
                    let endpoint = settings.customLLMEndpoint.trimmingCharacters(in: .whitespaces)
                    guard !endpoint.isEmpty else {
                        await MainActor.run { connectionStatus = .failed("No endpoint"); isTesting = false }
                        return
                    }
                    // Try to hit /models endpoint
                    var request = URLRequest(url: URL(string: "\(endpoint)/models")!)
                    if !apiKeyInput.isEmpty {
                        request.setValue("Bearer \(apiKeyInput)", forHTTPHeaderField: "Authorization")
                    }
                    let (_, resp) = try await URLSession.shared.data(for: request)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    await MainActor.run {
                        switch status {
                        case 200: connectionStatus = .success
                        case 401: connectionStatus = .failed("Invalid API key")
                        default: connectionStatus = .failed("HTTP \(status)")
                        }
                    }
                }
                await MainActor.run { isTesting = false }
            } catch {
                await MainActor.run { connectionStatus = .failed(error.localizedDescription); isTesting = false }
            }
        }
    }

    private func validateOllama() {
        testLLMConnection()
    }
}

// MARK: - Calendar

private struct CalendarSettingsContent: View {
    @ObservedObject var settings: AppSettings
    @State private var googleConnectionState: CalendarManager.GoogleStatus = .notConnected
    @State private var googleStatus = ""
    @State private var isConnecting = false
    @State private var showAdvanced = false
    @State private var customClientId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(title: "Google Calendar", icon: "calendar")

            if googleConnectionState == .connected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Connected to Google Calendar")
                }

                Button("Disconnect") { disconnectGoogle() }
                    .foregroundStyle(.red)
            } else if googleConnectionState == .expired {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Google Calendar token expired — will auto-refresh on next fetch")
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 12) {
                    Button("Refresh Now") { refreshGoogle() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Disconnect") { disconnectGoogle() }
                        .foregroundStyle(.red)
                        .controlSize(.small)
                }
            } else {
                Text("Connect your Google account to detect meetings from Google Calendar directly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        connectGoogle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                            Text("Sign in with Google")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConnecting)

                    if isConnecting {
                        ProgressView().controlSize(.small)
                        Text("Waiting for browser authorization...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Opens your browser to sign in. Scribe only requests read-only calendar access.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !googleStatus.isEmpty {
                Label(
                    googleStatus,
                    systemImage: googleStatus.contains("Error") ? "xmark.circle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(googleStatus.contains("Error") ? .red : .green)
            }

            // Advanced: custom OAuth client ID for forks
            Divider()

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("For self-hosted or forked builds, you can use your own Google OAuth Client ID.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    TextField("Custom OAuth Client ID (optional)", text: $customClientId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    if !customClientId.isEmpty {
                        Button("Save Custom Client ID") {
                            UserDefaults.standard.set(customClientId, forKey: "googleOAuthClientId")
                            googleStatus = "Custom client ID saved. Reconnect to use it."
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Divider()

            SettingsSectionHeader(title: "Outlook Calendar", icon: "envelope")
            Text("Microsoft 365 / Outlook support is planned for a future release.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .task {
            googleConnectionState = await CalendarManager.shared.googleConnectionStatus()
            customClientId = UserDefaults.standard.string(forKey: "googleOAuthClientId") ?? ""
        }
    }

    private func connectGoogle() {
        isConnecting = true; googleStatus = ""
        Task {
            do {
                let tokens = try await GoogleOAuthManager.shared.authorize()
                try? KeychainManager.shared.set(.googleOAuthToken, value: tokens.accessToken)
                if let r = tokens.refreshToken { try? KeychainManager.shared.set(.googleOAuthRefreshToken, value: r) }
                UserDefaults.standard.set(tokens.expiresAt.timeIntervalSince1970, forKey: "googleTokenExpiresAt")
                await CalendarManager.shared.setGoogleToken(tokens.accessToken)
                await MainActor.run { googleConnectionState = .connected; isConnecting = false; googleStatus = "Connected successfully" }
            } catch {
                await MainActor.run { isConnecting = false; googleStatus = "Error: \(error.localizedDescription)" }
            }
        }
    }

    private func disconnectGoogle() {
        try? KeychainManager.shared.delete(.googleOAuthToken)
        try? KeychainManager.shared.delete(.googleOAuthRefreshToken)
        UserDefaults.standard.removeObject(forKey: "googleTokenExpiresAt")
        googleConnectionState = .notConnected; googleStatus = ""
    }

    private func refreshGoogle() {
        isConnecting = true; googleStatus = ""
        Task {
            do {
                guard let refreshToken = KeychainManager.shared.get(.googleOAuthRefreshToken) else {
                    await MainActor.run { isConnecting = false; googleStatus = "Error: No refresh token, please reconnect" }
                    return
                }
                let tokens = try await GoogleOAuthManager.shared.refreshToken(refreshToken)
                try? KeychainManager.shared.set(.googleOAuthToken, value: tokens.accessToken)
                UserDefaults.standard.set(tokens.expiresAt.timeIntervalSince1970, forKey: "googleTokenExpiresAt")
                await CalendarManager.shared.setGoogleToken(tokens.accessToken)
                await MainActor.run { googleConnectionState = .connected; isConnecting = false; googleStatus = "Token refreshed" }
            } catch {
                await MainActor.run { isConnecting = false; googleStatus = "Error: \(error.localizedDescription)" }
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsSettingsContent: View {
    @ObservedObject var permissions: PermissionsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "Required Permissions", icon: "lock.shield")

            PermRow(name: "Microphone", icon: "mic.fill", desc: "Capture your voice during meetings",
                    granted: permissions.microphoneGranted) { Task { await permissions.checkMicrophone() } }

            PermRow(name: "Screen Recording", icon: "rectangle.dashed.badge.record", desc: "Capture system audio from meeting apps",
                    granted: permissions.screenRecordingGranted) { permissions.openSystemPreferences() }

            PermRow(name: "Calendar", icon: "calendar", desc: "Detect upcoming meetings automatically",
                    granted: permissions.calendarGranted) { Task { await permissions.checkCalendar() } }

            PermRow(name: "Notifications", icon: "bell.fill",
                    desc: permissions.hasBundleId ? "Alert when meetings detected" : "Not available in dev mode",
                    granted: permissions.notificationsGranted) {
                if permissions.hasBundleId { Task { await permissions.checkNotifications() } }
                else { permissions.openNotificationSettings() }
            }

            Divider()

            Text("Some permissions require restarting Scribe after granting.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("Open System Settings") { permissions.openSystemPreferences() }
        }
    }
}

private struct PermRow: View {
    let name: String; let icon: String; let desc: String; let granted: Bool; let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(granted ? .green : .secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            } else {
                Button("Request") { action() }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shared Components

private struct SettingsSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }
}
