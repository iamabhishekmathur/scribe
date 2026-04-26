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
                .tint(MonoColors.accent)
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
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            // Navigation
            HStack {
                if currentStep != .welcome {
                    Button("Back") {
                        withAnimation(Anim.panel) {
                            currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome
                        }
                    }
                    .buttonStyle(MonoSecondaryButtonStyle())
                }
                Spacer()
                if currentStep == .complete {
                    Button("Get Started") {
                        settings.hasCompletedOnboarding = true
                        dismiss()
                    }
                    .buttonStyle(MonoPrimaryButtonStyle())
                } else {
                    Button("Next") {
                        withAnimation(Anim.panel) {
                            currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .complete
                        }
                    }
                    .buttonStyle(MonoPrimaryButtonStyle())
                }
            }
            .padding()
        }
        .frame(width: 520, height: 440)
        .task {
            await permissions.refreshStatus()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(MonoColors.accent)
            Text("Welcome to Scribe")
                .font(MonoFont.sans(size: TypeScale.xxxl, weight: .bold))
            Text("Your AI meeting notetaker that captures audio invisibly, transcribes in real-time, and generates smart summaries. All data stays on your Mac.")
                .font(MonoFont.sans(size: TypeScale.md))
                .foregroundStyle(MonoColors.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions")
                .font(MonoFont.sans(size: TypeScale.xl, weight: .bold))
            Text("Scribe needs a few permissions to work. Click each to grant access.")
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)

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

    @State private var useLocalTranscription = true

    private var transcriptionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription")
                .font(MonoFont.sans(size: TypeScale.xl, weight: .bold))
            Text("Choose how Scribe transcribes your meeting audio. You can change this later in Settings.")
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)

            HStack(alignment: .top, spacing: 14) {
                modelCard(
                    isSelected: useLocalTranscription,
                    badge: "LOCAL", badgeColor: MonoColors.success, suffix: " · recommended",
                    title: "Whisper.cpp · large-v3",
                    desc: "Runs on-device. Audio never leaves your Mac. Perfect for confidential meetings.",
                    specs: [("speed", "1.4× realtime · M2"), ("accuracy", "94% WER · english"), ("privacy", "100% local · no network"), ("cost", "free · ~3GB disk")]
                ) { useLocalTranscription = true }

                modelCard(
                    isSelected: !useLocalTranscription,
                    badge: "CLOUD", badgeColor: MonoColors.warn, suffix: nil,
                    title: "OpenAI · whisper-1",
                    desc: "Faster and slightly more accurate. Audio is sent to OpenAI's API.",
                    specs: [("speed", "3.2× realtime"), ("accuracy", "97% WER · english"), ("privacy", "sends audio · 30-day retention"), ("cost", "$0.006/min · pay-per-use")]
                ) { useLocalTranscription = false }
            }

            if !useLocalTranscription {
                let keychainKey = KeychainManager.shared.apiKeyForTranscriptionProvider(settings.transcriptionProvider)
                SecureField("API Key for \(settings.transcriptionProvider.rawValue)", text: Binding(
                    get: { KeychainManager.shared.get(keychainKey) ?? "" },
                    set: { try? KeychainManager.shared.set(keychainKey, value: $0) }
                ))
                .textFieldStyle(MonoTextFieldStyle())
            }
        }
    }

    private func modelCard(
        isSelected: Bool, badge: String, badgeColor: Color, suffix: String?,
        title: String, desc: String, specs: [(String, String)], onTap: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(badge)
                    .font(MonoFont.mono(size: 9.5, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(badgeColor, in: RoundedRectangle(cornerRadius: 2))
                    .foregroundStyle(.white)
                if let suffix {
                    Text(suffix)
                        .font(MonoFont.mono(size: TypeScale.xs))
                        .foregroundStyle(isSelected ? MonoColors.accentText : MonoColors.textFaint)
                }
                Spacer()
                Circle()
                    .stroke(isSelected ? MonoColors.accent : MonoColors.borderStrong, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if isSelected {
                            Circle().fill(MonoColors.accent).frame(width: 8, height: 8)
                        }
                    }
            }

            Text(title).font(MonoFont.mono(size: 14, weight: .semibold))
            Text(desc)
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 4) {
                ForEach(specs, id: \.0) { key, val in
                    HStack(spacing: 0) {
                        Text(key)
                            .font(MonoFont.mono(size: 10.5))
                            .foregroundStyle(MonoColors.textFaint)
                            .frame(width: 80, alignment: .leading)
                        Text(val)
                            .font(MonoFont.mono(size: 10.5))
                            .foregroundStyle(MonoColors.text)
                    }
                }
            }
            .padding(.top, 6)
            .overlay(alignment: .top) {
                Rectangle().fill(MonoColors.divider).frame(height: 1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? MonoColors.accentBg : MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(isSelected ? MonoColors.accentBorder : MonoColors.divider, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var llmStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI / LLM Provider")
                .font(MonoFont.sans(size: TypeScale.xl, weight: .bold))
            Text("Choose an AI provider for summaries and chat.")
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)

            MonoRadioList(
                selection: $settings.llmProvider,
                options: LLMProviderType.allCases.map { ($0.rawValue, $0) }
            )

            switch settings.llmProvider {
            case .claude, .openAI:
                let keychainKey = KeychainManager.shared.apiKeyForLLMProvider(settings.llmProvider)
                SecureField("API Key", text: Binding(
                    get: { KeychainManager.shared.get(keychainKey) ?? "" },
                    set: { try? KeychainManager.shared.set(keychainKey, value: $0) }
                ))
                .textFieldStyle(MonoTextFieldStyle())
            case .ollama:
                TextField("Endpoint", text: $settings.ollamaEndpoint)
                    .textFieldStyle(MonoTextFieldStyle())
                TextField("Model", text: $settings.ollamaModel)
                    .textFieldStyle(MonoTextFieldStyle())
            case .custom:
                TextField("Endpoint URL", text: $settings.customLLMEndpoint)
                    .textFieldStyle(MonoTextFieldStyle())
                TextField("Model name", text: $settings.customLLMModel)
                    .textFieldStyle(MonoTextFieldStyle())
            }
        }
    }

    private var completeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(MonoColors.success)
            Text("You're All Set!")
                .font(MonoFont.sans(size: TypeScale.xxxl, weight: .bold))
            Text("Scribe will run in your menu bar. Start a meeting or join a call — Scribe will detect it and offer to record.")
                .font(MonoFont.sans(size: TypeScale.base))
                .foregroundStyle(MonoColors.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(alignment: .leading, spacing: 8) {
                Label("Click the menu bar icon to start/stop recording", systemImage: "menubar.rectangle")
                Label("Use the floating overlay during meetings", systemImage: "rectangle.on.rectangle")
                Label("Review meetings in the main window", systemImage: "list.bullet.rectangle")
            }
            .font(MonoFont.sans(size: TypeScale.base))
            .foregroundStyle(MonoColors.textMuted)
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
        HStack(spacing: Spacing.standard) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 24)
                .foregroundStyle(granted ? MonoColors.success : MonoColors.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(MonoFont.sans(size: TypeScale.base, weight: .medium))
                    .foregroundStyle(MonoColors.text)
                Text(description)
                    .font(MonoFont.sans(size: TypeScale.sm))
                    .foregroundStyle(MonoColors.textMuted)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MonoColors.success)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Grant") { action() }
                    .buttonStyle(MonoSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(MonoColors.border, lineWidth: 1))
        .animation(Anim.standard, value: granted)
    }
}
