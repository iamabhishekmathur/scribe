import SwiftUI

/// Lightweight error toast that slides down from the top of a view
struct ErrorBanner: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MonoColors.live)
                    Text(message)
                        .font(MonoFont.mono(size: TypeScale.sm, weight: .semibold))
                        .foregroundStyle(MonoColors.text)
                    Spacer()
                    Button {
                        withAnimation(Anim.fast) { self.message = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(MonoFont.mono(size: TypeScale.xs))
                            .foregroundStyle(MonoColors.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(MonoColors.bgElev, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay(
                    HStack {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(MonoColors.live)
                            .frame(width: 3)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                )
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        await MainActor.run {
                            withAnimation(Anim.fast) { self.message = nil }
                        }
                    }
                }
            }
        }
        .animation(Anim.standard, value: message)
    }
}

extension View {
    func errorBanner(_ message: Binding<String?>) -> some View {
        modifier(ErrorBanner(message: message))
    }
}
