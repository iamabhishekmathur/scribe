import SwiftUI
import ScribeCore

/// AI chat interface during meetings
public struct AIChatView: View {
    let meetingId: UUID
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var chatService = ChatService()
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
                                    .font(MonoFont.mono(size: TypeScale.xs))
                                    .foregroundStyle(MonoColors.textMuted)
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
                    .font(MonoFont.sans(size: TypeScale.sm))
                    .lineLimit(1...3)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(MonoColors.accent)
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
            await chatService.start(meetingId: meetingId)
            do {
                let response = try await chatService.ask(question)
                await MainActor.run {
                    withAnimation(Anim.panel) {
                        messages.append(ChatMessage(role: .assistant, content: response))
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    withAnimation(Anim.panel) {
                        messages.append(ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
                    }
                    isLoading = false
                }
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
        HStack(alignment: .top, spacing: 10) {
            Text(message.role == .user ? "you ›" : "scribe")
                .font(MonoFont.mono(size: TypeScale.xs, weight: .semibold))
                .foregroundStyle(message.role == .user ? MonoColors.text : MonoColors.accent)
                .frame(width: 44, alignment: .trailing)

            Text(message.content)
                .font(MonoFont.sans(size: TypeScale.sm))
                .foregroundStyle(MonoColors.text)
                .textSelection(.enabled)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(MonoFont.mono(size: TypeScale.xs))
                .foregroundStyle(MonoColors.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isHovered ? MonoColors.bgHover : MonoColors.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(MonoColors.border, lineWidth: 1))
        }
        .buttonStyle(ScribeButtonStyle())
        .onHover { isHovered = $0 }
        .animation(Anim.fast, value: isHovered)
    }
}
