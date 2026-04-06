import SwiftUI
import ScribeCore

/// First-launch onboarding wizard: permissions → transcription → LLM → calendar
public struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var permissions = PermissionsManager.shared
    @State private var currentStep: OnboardingStep = .welcome
    @Environment(\.dismiss) private var dismiss

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case permissions
        case transcription
        case llm
        case complete
    }

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Progress
            ProgressView(value: Double(currentStep.rawValue), total: Double(OnboardingStep.allCases.count - 1))
                .padding(.horizontal)
                .padding(.top)

            // Content
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .permissions:
                    permissionsStep
                case .transcription:
                    transcriptionStep
                case .llm:
                    llmStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

            // Navigation
            HStack {
                if currentStep != .welcome {
                    Button("Back") {
                        withAnimation {
                            currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome
                        }
                    }
                }
                Spacer()
                if currentStep == .complete {
                    Button("Get Started") {
                        settings.hasCompletedOnboarding = true
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Next") {
                        withAnimation {
                            currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .complete
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 440)
        .task {
            await permissions.checkAll()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Welcome to Scribe")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Your AI meeting notetaker that captures audio invisibly, transcribes in real-time, and generates smart summaries. All data stays on your Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions")
                .font(.title)
                .fontWeight(.bold)
            Text("Scribe needs a few permissions to work. Click each to grant access.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                OnboardingPermissionRow(
                    name: "Microphone",
                    icon: "mic.fill",
                    description: "Capture your voice",
                    granted: permissions.microphoneGranted,
                    action: { Task { await permissions.checkMicrophone() } }
                )
                OnboardingPermissionRow(
                    name: "Screen Recording",
                    icon: "rectangle.dashed.badge.record",
                    description: "Capture system audio from meetings",
                    granted: permissions.screenRecordingGranted,
                    action: { Task { await permissions.checkScreenRecording() } }
                )
                OnboardingPermissionRow(
                    name: "Calendar",
                    icon: "calendar",
                    description: "Detect upcoming meetings",
                    granted: permissions.calendarGranted,
                    action: { Task { await permissions.checkCalendar() } }
                )
                OnboardingPermissionRow(
                    name: "Notifications",
                    icon: "bell.fill",
                    description: "Alert you when meetings are detected",
                    granted: permissions.notificationsGranted,
                    action: { Task { await permissions.checkNotifications() } }
                )
            }
        }
    }

    private var transcriptionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Provider")
                .font(.title)
                .fontWeight(.bold)
            Text("Choose a cloud service to transcribe your meeting audio.")
                .foregroundStyle(.secondary)

            Picker("Provider", selection: $settings.transcriptionProvider) {
                ForEach(TranscriptionProviderType.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.radioGroup)

            let keychainKey = KeychainManager.shared.apiKeyForTranscriptionProvider(settings.transcriptionProvider)
            SecureField("API Key for \(settings.transcriptionProvider.rawValue)", text: Binding(
                get: { KeychainManager.shared.get(keychainKey) ?? "" },
                set: { try? KeychainManager.shared.set(keychainKey, value: $0) }
            ))
            .textFieldStyle(.roundedBorder)

            Text("You can change this later in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var llmStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI / LLM Provider")
                .font(.title)
                .fontWeight(.bold)
            Text("Choose an AI provider for summaries and chat.")
                .foregroundStyle(.secondary)

            Picker("Provider", selection: $settings.llmProvider) {
                ForEach(LLMProviderType.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.radioGroup)

            switch settings.llmProvider {
            case .claude, .openAI:
                let keychainKey = KeychainManager.shared.apiKeyForLLMProvider(settings.llmProvider)
                SecureField("API Key", text: Binding(
                    get: { KeychainManager.shared.get(keychainKey) ?? "" },
                    set: { try? KeychainManager.shared.set(keychainKey, value: $0) }
                ))
                .textFieldStyle(.roundedBorder)
            case .ollama:
                TextField("Endpoint", text: $settings.ollamaEndpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $settings.ollamaModel)
                    .textFieldStyle(.roundedBorder)
            case .custom:
                TextField("Endpoint URL", text: $settings.customLLMEndpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Model name", text: $settings.customLLMModel)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var completeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Scribe will run in your menu bar. Start a meeting or join a call — Scribe will detect it and offer to record.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 8) {
                Label("Click the menu bar icon to start/stop recording", systemImage: "menubar.rectangle")
                Label("Use the floating overlay during meetings", systemImage: "rectangle.on.rectangle")
                Label("Review meetings in the main window", systemImage: "list.bullet.rectangle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

struct OnboardingPermissionRow: View {
    let name: String
    let icon: String
    let description: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(granted ? .green : .secondary)

            VStack(alignment: .leading) {
                Text(name)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}
