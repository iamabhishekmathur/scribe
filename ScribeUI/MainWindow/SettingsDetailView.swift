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
                        .transition(.opacity)
                case .transcription:
                    TranscriptionSettingsContent(settings: settings)
                        .transition(.opacity)
                case .llm:
                    LLMSettingsContent(settings: settings)
                        .transition(.opacity)
                case .calendar:
                    CalendarSettingsContent(settings: settings)
                        .transition(.opacity)
                case .permissions:
                    PermissionsSettingsContent(permissions: permissions)
                        .transition(.opacity)
                }
            }
            .animation(Anim.standard, value: selectedSection)
            .padding(24)
        }
        .task {
            await permissions.refreshStatus()
        }
    }
}

// MARK: - General

private struct GeneralSettingsContent: View {
    @ObservedObject var settings: AppSettings
    @State private var showFolderPicker = false

    private var displayPath: String {
        if settings.meetingStoragePath.isEmpty {
            return "~/.scribe/meetings/"
        }
        return settings.meetingStoragePath
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(title: "Appearance", icon: "circle.lefthalf.filled")

            Text("Choose how Scribe looks. System follows your macOS appearance.")
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)

            MonoSegmentedControl(
                selection: $settings.appearance,
                options: [
                    ("System", "system"),
                    ("Dark", "dark"),
                    ("Light", "light"),
                ]
            )
            .frame(maxWidth: 240)

            Divider()

            SettingsSectionHeader(title: "Meeting Storage", icon: "folder")

            Text("Choose where Scribe saves meeting files. Use an iCloud Drive or Dropbox folder to sync across devices.")
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.meetingStoragePath.isEmpty ? "Default" : "Custom")
                        .font(MonoFont.sans(size: TypeScale.base, weight: .medium))
                    Text(displayPath)
                        .font(MonoFont.sans(size: TypeScale.sm))
                        .foregroundStyle(MonoColors.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Choose Folder…") {
                    showFolderPicker = true
                }
                .buttonStyle(MonoSecondaryButtonStyle())

                if !settings.meetingStoragePath.isEmpty {
                    Button("Reset") {
                        settings.meetingStoragePath = ""
                    }
                    .buttonStyle(MonoSecondaryButtonStyle())
                }
            }
            .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    settings.meetingStoragePath = url.path
                }
            }

            Divider()

            SettingsSectionHeader(title: "Content Font", icon: "textformat")

            Text("Font used for meeting summaries, notes, and the editor.")
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(ContentFontOption.allCases) { option in
                    FontPickerRow(option: option, isSelected: settings.contentFont == option.rawValue) {
                        settings.contentFont = option.rawValue
                    }
                }
            }
            .padding(.leading, 4)

            Divider()

            SettingsSectionHeader(title: "Meeting Detection", icon: "antenna.radiowaves.left.and.right")

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Auto-detect meetings", isOn: $settings.autoDetectMeetings)
                    .toggleStyle(MonoCheckboxToggleStyle())
                Toggle("Auto-start recording", isOn: $settings.autoStartRecording)
                    .toggleStyle(MonoCheckboxToggleStyle())
                Toggle("Show overlay during meetings", isOn: $settings.showOverlayDuringMeetings)
                    .toggleStyle(MonoCheckboxToggleStyle())
            }
            .padding(.leading, 4)

            Divider()

            SettingsSectionHeader(title: "Screen Context", icon: "rectangle.badge.checkmark")

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Capture screen context during screen share", isOn: $settings.screenContextEnabled)
                    .toggleStyle(MonoCheckboxToggleStyle())
                if settings.screenContextEnabled {
                    HStack(spacing: Spacing.compact) {
                        Text("Capture interval:")
                            .font(MonoFont.sans(size: TypeScale.base))
                            .foregroundStyle(MonoColors.textMuted)
                        TextField("", value: $settings.screenContextInterval, format: .number)
                            .frame(width: 56)
                            .textFieldStyle(MonoTextFieldStyle())
                        Text("seconds")
                            .font(MonoFont.sans(size: TypeScale.base))
                            .foregroundStyle(MonoColors.textMuted)
                    }
                    .padding(.leading, 22)
                }
            }
            .padding(.leading, 4)

            Divider()

            SettingsSectionHeader(title: "Disk Usage", icon: "internaldrive")

            DiskUsageCard()

        }
    }
}

// MARK: - Disk Usage Card

private struct DiskUsageCard: View {
    @State private var totalSize = "Calculating..."
    @State private var meetingCount = 0
    @State private var audioHours: Double = 0
    @State private var audioBytes: Int64 = 0
    @State private var transcriptBytes: Int64 = 0
    @State private var summaryBytes: Int64 = 0
    @State private var otherBytes: Int64 = 0
    @State private var isLoaded = false

    private var totalBytes: Int64 { audioBytes + transcriptBytes + summaryBytes + otherBytes }

    private func fraction(_ bytes: Int64) -> CGFloat {
        guard totalBytes > 0 else { return 0 }
        return CGFloat(bytes) / CGFloat(totalBytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(totalSize)
                    .font(MonoFont.mono(size: 18, weight: .semibold))
                if isLoaded {
                    Text("· \(meetingCount) meetings · \(String(format: "%.1f", audioHours))h audio")
                        .font(MonoFont.mono(size: TypeScale.sm))
                        .foregroundStyle(MonoColors.textMuted)
                }
            }

            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(MonoColors.accent)
                        .frame(width: geo.size.width * fraction(audioBytes))
                    Rectangle().fill(MonoColors.accent.opacity(0.5))
                        .frame(width: geo.size.width * fraction(transcriptBytes))
                    Rectangle().fill(MonoColors.text.opacity(0.5))
                        .frame(width: geo.size.width * fraction(summaryBytes))
                    Rectangle().fill(MonoColors.text.opacity(0.25))
                        .frame(width: geo.size.width * fraction(otherBytes))
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 8)
            .background(MonoColors.bgElev, in: RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(MonoColors.divider, lineWidth: 1))

            HStack(spacing: 12) {
                diskLegend(MonoColors.accent, "audio", formatBytes(audioBytes))
                diskLegend(MonoColors.accent.opacity(0.5), "transcripts", formatBytes(transcriptBytes))
                diskLegend(MonoColors.text.opacity(0.5), "summaries", formatBytes(summaryBytes))
                diskLegend(MonoColors.text.opacity(0.25), "other", formatBytes(otherBytes))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(MonoColors.divider, lineWidth: 1))
        .task { await computeUsage() }
    }

    private func diskLegend(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 8)
            Text("\(label) · \(value)")
                .font(MonoFont.mono(size: 10.5))
                .foregroundStyle(MonoColors.textMuted)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func computeUsage() async {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let scribeDir = appSupport.appendingPathComponent("Scribe").path
        let fm = FileManager.default

        var audio: Int64 = 0, transcript: Int64 = 0, summary: Int64 = 0, other: Int64 = 0
        var meetings = 0

        if let enumerator = fm.enumerator(atPath: scribeDir) {
            while let file = enumerator.nextObject() as? String {
                let fullPath = (scribeDir as NSString).appendingPathComponent(file)
                guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                      let size = attrs[.size] as? Int64 else { continue }
                let ext = (file as NSString).pathExtension.lowercased()
                switch ext {
                case "m4a", "wav", "mp3", "caf", "aac", "opus": audio += size
                case "json" where file.contains("transcript"): transcript += size
                case "json" where file.contains("summary"): summary += size
                case "sqlite", "sqlite-wal", "sqlite-shm": other += size
                default: other += size
                }
            }
        }

        // Count meetings from database
        let allMeetings = (try? await MeetingStore.shared.getAllMeetings()) ?? []
        meetings = allMeetings.count

        let totalAudioHrs = Double(audio) / (16_000.0 * 3600.0)
        let total = audio + transcript + summary + other

        let formatted: String
        if total > 1_000_000_000 { formatted = String(format: "%.1f GB", Double(total) / 1e9) }
        else if total > 1_000_000 { formatted = String(format: "%.0f MB", Double(total) / 1e6) }
        else { formatted = String(format: "%.0f KB", Double(total) / 1e3) }

        await MainActor.run {
            totalSize = total > 0 ? formatted : "< 1 MB"
            meetingCount = meetings
            audioHours = totalAudioHrs
            audioBytes = max(audio, 1)
            transcriptBytes = max(transcript, 1)
            summaryBytes = max(summary, 1)
            otherBytes = max(other, 1)
            isLoaded = true
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

            MonoRadioList(
                selection: $settings.transcriptionProvider,
                options: TranscriptionProviderType.allCases.map { ($0.rawValue, $0) }
            )

            Text(providerDescription)
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)

            Divider()

            SettingsSectionHeader(title: "API Key", icon: "key")

            SecureField("API key for \(settings.transcriptionProvider.rawValue)", text: $apiKeyInput)
                .textFieldStyle(MonoTextFieldStyle())
                .onAppear { loadKey() }
                .onChange(of: settings.transcriptionProvider) { _ in
                    loadKey()
                    connectionStatus = .idle
                    keySaved = false
                }

            HStack(spacing: Spacing.compact) {
                Button("Save Key") {
                    let k = KeychainManager.shared.apiKeyForTranscriptionProvider(settings.transcriptionProvider)
                    try? KeychainManager.shared.set(k, value: apiKeyInput)
                    keySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
                }
                .buttonStyle(MonoPrimaryButtonStyle())
                .disabled(apiKeyInput.isEmpty)

                Button("Test Connection") {
                    connectionStatus = .testing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        connectionStatus = apiKeyInput.isEmpty ? .failed("No API key") : .success
                    }
                }
                .buttonStyle(MonoSecondaryButtonStyle())
                .disabled(apiKeyInput.isEmpty)

                Spacer()

                switch connectionStatus {
                case .idle:
                    if keySaved {
                        Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(MonoColors.success).font(MonoFont.sans(size: TypeScale.sm))
                    }
                case .testing:
                    ProgressView().controlSize(.small)
                case .success:
                    Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(MonoColors.success).font(MonoFont.sans(size: TypeScale.sm))
                case .failed(let msg):
                    Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(MonoColors.live).font(MonoFont.sans(size: TypeScale.sm))
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

            MonoRadioList(
                selection: $settings.llmProvider,
                options: LLMProviderType.allCases.map { ($0.rawValue, $0) }
            )

            Text(providerDescription)
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)

            Divider()

            switch settings.llmProvider {
            case .claude, .openAI:
                SettingsSectionHeader(title: "API Key", icon: "key")

                SecureField("API key for \(settings.llmProvider.rawValue)", text: $apiKeyInput)
                    .textFieldStyle(MonoTextFieldStyle())
                    .onAppear { loadKey() }
                    .onChange(of: settings.llmProvider) { _ in loadKey(); validationError = nil; connectionStatus = .idle }

                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(MonoColors.live).font(MonoFont.sans(size: TypeScale.sm))
                }

                HStack(spacing: Spacing.compact) {
                    Button("Save Key") { saveKey() }
                        .buttonStyle(MonoPrimaryButtonStyle())
                        .disabled(apiKeyInput.isEmpty)

                    Button("Test Connection") { testLLMConnection() }
                        .buttonStyle(MonoSecondaryButtonStyle())
                        .disabled(apiKeyInput.isEmpty || isTesting)

                    Spacer()

                    connectionStatusView
                }

            case .ollama:
                SettingsSectionHeader(title: "Configuration", icon: "server.rack")

                MonoLabeledField(label: "Endpoint") {
                    TextField("http://localhost:11434", text: $settings.ollamaEndpoint)
                        .textFieldStyle(MonoTextFieldStyle())
                }
                MonoLabeledField(label: "Model") {
                    TextField("llama3", text: $settings.ollamaModel)
                        .textFieldStyle(MonoTextFieldStyle())
                }

                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(MonoColors.live).font(MonoFont.sans(size: TypeScale.sm))
                }

                HStack(spacing: Spacing.compact) {
                    Button("Test Connection") { testLLMConnection() }
                        .buttonStyle(MonoSecondaryButtonStyle())
                        .disabled(isTesting)
                    Spacer()
                    connectionStatusView
                }

            case .custom:
                SettingsSectionHeader(title: "Custom Provider", icon: "server.rack")

                MonoLabeledField(label: "Endpoint") {
                    TextField("https://api.example.com/v1", text: $settings.customLLMEndpoint)
                        .textFieldStyle(MonoTextFieldStyle())
                }
                MonoLabeledField(label: "Model") {
                    TextField("gpt-4o", text: $settings.customLLMModel)
                        .textFieldStyle(MonoTextFieldStyle())
                }
                SecureField("API Key (optional)", text: $apiKeyInput)
                    .textFieldStyle(MonoTextFieldStyle())
                    .onAppear { apiKeyInput = KeychainManager.shared.get(.customLLMAPIKey) ?? "" }

                HStack(spacing: Spacing.compact) {
                    Button("Save Key") {
                        try? KeychainManager.shared.set(.customLLMAPIKey, value: apiKeyInput)
                        LLMManager.shared.refresh()
                    }
                    .buttonStyle(MonoPrimaryButtonStyle())
                    .disabled(settings.customLLMEndpoint.isEmpty)

                    Button("Test Connection") { testLLMConnection() }
                        .buttonStyle(MonoSecondaryButtonStyle())
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
                Text("Testing...").font(MonoFont.sans(size: TypeScale.sm)).foregroundStyle(MonoColors.textMuted)
            }
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(MonoColors.success).font(MonoFont.sans(size: TypeScale.sm))
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(MonoColors.live).font(MonoFont.sans(size: TypeScale.sm))
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
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MonoColors.success)
                    Text("Connected to Google Calendar")
                        .font(MonoFont.sans(size: TypeScale.base))
                        .foregroundStyle(MonoColors.text)
                }

                Button("Disconnect") { disconnectGoogle() }
                    .buttonStyle(MonoPrimaryButtonStyle(danger: true))
            } else if googleConnectionState == .expired {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MonoColors.warn)
                    Text("Google Calendar token expired — will auto-refresh on next fetch")
                        .font(MonoFont.sans(size: TypeScale.sm))
                        .foregroundStyle(MonoColors.warn)
                }

                HStack(spacing: Spacing.compact) {
                    Button("Refresh Now") { refreshGoogle() }
                        .buttonStyle(MonoPrimaryButtonStyle())
                    Button("Disconnect") { disconnectGoogle() }
                        .buttonStyle(MonoPrimaryButtonStyle(danger: true))
                }
            } else {
                Text("Connect your Google account to detect meetings from Google Calendar directly.")
                    .font(MonoFont.sans(size: TypeScale.base))
                    .foregroundStyle(MonoColors.textMuted)

                HStack(spacing: Spacing.compact) {
                    Button {
                        connectGoogle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                            Text("Sign in with Google")
                        }
                    }
                    .buttonStyle(MonoPrimaryButtonStyle())
                    .disabled(isConnecting)

                    if isConnecting {
                        ProgressView().controlSize(.small)
                        Text("Waiting for browser authorization…")
                            .font(MonoFont.sans(size: TypeScale.sm))
                            .foregroundStyle(MonoColors.textMuted)
                    }
                }

                Text("Opens your browser to sign in. Scribe only requests read-only calendar access.")
                    .font(MonoFont.sans(size: TypeScale.sm))
                    .foregroundStyle(MonoColors.textFaint)
            }

            if !googleStatus.isEmpty {
                Label(
                    googleStatus,
                    systemImage: googleStatus.contains("Error") ? "xmark.circle.fill" : "checkmark.circle.fill"
                )
                .font(MonoFont.sans(size: TypeScale.sm))
                .foregroundStyle(googleStatus.contains("Error") ? MonoColors.live : MonoColors.success)
            }

            // Advanced: custom OAuth client ID for forks
            Divider()

            MonoDisclosure("Advanced", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: Spacing.compact) {
                    Text("For self-hosted or forked builds, you can use your own Google OAuth Client ID.")
                        .font(MonoFont.sans(size: TypeScale.sm))
                        .foregroundStyle(MonoColors.textFaint)

                    TextField("Custom OAuth Client ID (optional)", text: $customClientId)
                        .textFieldStyle(MonoTextFieldStyle())

                    if !customClientId.isEmpty {
                        Button("Save Custom Client ID") {
                            UserDefaults.standard.set(customClientId, forKey: "googleOAuthClientId")
                            googleStatus = "Custom client ID saved. Reconnect to use it."
                        }
                        .buttonStyle(MonoSecondaryButtonStyle())
                    }
                }
            }

            Divider()

            SettingsSectionHeader(title: "Outlook Calendar", icon: "envelope")
            Text("Microsoft 365 / Outlook support is planned for a future release.")
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)
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
                .font(MonoFont.sans(size: TypeScale.sm))
                .foregroundStyle(MonoColors.textFaint)

            Button("Open System Settings") { permissions.openSystemPreferences() }
                .buttonStyle(MonoSecondaryButtonStyle())
        }
    }
}

private struct PermRow: View {
    let name: String; let icon: String; let desc: String; let granted: Bool; let action: () -> Void
    var body: some View {
        HStack(spacing: Spacing.standard) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(granted ? MonoColors.success : MonoColors.textMuted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(MonoFont.sans(size: TypeScale.base, weight: .medium))
                Text(desc).font(MonoFont.sans(size: TypeScale.sm)).foregroundStyle(MonoColors.textMuted)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(MonoColors.success)
                    .font(MonoFont.sans(size: TypeScale.sm))
            } else {
                Button("Request") { action() }
                    .buttonStyle(MonoSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.standard)
        .padding(.vertical, Spacing.compact)
        .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(MonoColors.border, lineWidth: 1))
    }
}

// MARK: - Font Picker Row

private struct FontPickerRow: View {
    let option: ContentFontOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("The quick brown fox")
                .font(option.font(size: 13))
                .frame(width: 150, alignment: .leading)

            Text(option.displayName)
                .font(MonoFont.sans(size: TypeScale.sm))
                .foregroundStyle(MonoColors.textMuted)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(MonoFont.sans(size: TypeScale.sm))
                    .foregroundStyle(MonoColors.accent)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, Spacing.compact)
        .background(isSelected ? MonoColors.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: Radius.md))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

// MARK: - Shared Components

private struct SettingsSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(MonoColors.textMuted)
            Text(title)
                .font(MonoFont.sans(size: TypeScale.lg, weight: .semibold))
                .foregroundStyle(MonoColors.text)
        }
    }
}

/// Mono-styled labeled field (replaces SwiftUI LabeledContent which has heavy default styling)
private struct MonoLabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Spacing.standard) {
            Text(label)
                .font(MonoFont.mono(size: TypeScale.sm))
                .foregroundStyle(MonoColors.textMuted)
                .frame(width: 80, alignment: .trailing)
            content()
        }
    }
}
