import SwiftUI
import ScribeCore

/// AI chat interface during meetings
public struct AIChatView: View {
    let meetingId: UUID
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    public init(meetingId: UUID) {
        self.meetingId = meetingId
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Quick actions
            quickActions

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        if isLoading {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Ask about the meeting...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .lineLimit(1...3)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                QuickActionButton(title: "What did I miss?") {
                    askQuestion("What did I miss? Summarize the key points discussed so far.")
                }
                QuickActionButton(title: "What are they asking?") {
                    askQuestion("What is being asked or discussed right now?")
                }
                QuickActionButton(title: "Action items") {
                    askQuestion("What action items have been mentioned so far?")
                }
                QuickActionButton(title: "Key decisions") {
                    askQuestion("What decisions have been made in this meeting so far?")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        askQuestion(text)
    }

    private func askQuestion(_ question: String) {
        withAnimation(Anim.panel) {
            messages.append(ChatMessage(role: .user, content: question))
        }
        isLoading = true

        Task {
            // TODO: Wire to LLMManager with transcript context
            // For now, placeholder response
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                withAnimation(Anim.panel) {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: "AI chat will be connected in Phase 6 (AI Features). This will use your configured LLM with the live transcript as context."
                    ))
                }
                isLoading = false
            }
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()

    enum Role {
        case user, assistant
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    message.role == .user ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .textSelection(.enabled)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isHovered ? Color.primary.opacity(0.08) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(ScribeButtonStyle())
        .onHover { isHovered = $0 }
        .animation(Anim.fast, value: isHovered)
    }
}
