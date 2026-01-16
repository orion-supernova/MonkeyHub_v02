import SwiftUI
import Combine

struct MessagesListView: View {
    let viewModel: ChatRoomViewModel
    let isLoading: Bool
    let onImageTapped: (URL) -> Void
    let imageZoomNamespace: Namespace.ID
    @State private var activeReactionPickerMessageId: String?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showScrollToBottom = false
    @State private var scrollToBottom = false

    // Cache userId once to avoid UserDefaults reads during scroll
    private var currentUserId: String {
        userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
    }

    var body: some View {
        UIKitScrollView(
            content: messagesContent,
            firstItemId: viewModel.messages.first?.id,
            itemCount: viewModel.messages.count,
            scrollToBottom: $scrollToBottom,
            onNearTop: {
                if !viewModel.isFetchingOlderMessages {
                    Task { await viewModel.loadOlderMessages() }
                }
            },
            onAtBottomChanged: { isAtBottom in
                showScrollToBottom = !isAtBottom
            }
        )
        .background(Color.clear)
        .onTapGesture {
            activeReactionPickerMessageId = nil
            #if canImport(UIKit)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                scrollToBottom = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .modifier(LiquidGlassModifier(cornerRadius: 19))
            }
            .padding(.trailing, 20)
            .padding(.bottom, 100)
            .opacity(showScrollToBottom ? 1 : 0)
            .scaleEffect(showScrollToBottom ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.2), value: showScrollToBottom)
        }
    }

    // MARK: - Messages Content (Pure SwiftUI)

    private var messagesContent: some View {
        VStack(spacing: 8) {
            // Top spacer with loading indicator
            Color.clear
                .frame(height: verticalSizeClass == .compact ? 80 : 120)
                .overlay(alignment: .bottom) {
                    if viewModel.isFetchingOlderMessages {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.bottom, 8)
                    }
                }

            ForEach(viewModel.messages) { message in
                MessageView(
                    message: message,
                    currentUserId: currentUserId,
                    isCurrentUser: message.senderId == currentUserId,
                    onImageTapped: onImageTapped,
                    onDelete: {
                        Task { await viewModel.deleteMessage(message.id) }
                    },
                    showReactionPicker: Binding(
                        get: { activeReactionPickerMessageId == message.id },
                        set: { activeReactionPickerMessageId = $0 ? message.id : nil }
                    ),
                    imageZoomNamespace: imageZoomNamespace
                )
                .padding(.horizontal)
            }

            if let typingText = viewModel.typingText {
                TypingIndicatorView(text: typingText)
                    .padding(.horizontal)
            }

            // Bottom buffer for floating input area
            Color.clear.frame(height: verticalSizeClass == .compact ? 60 : 80)
        }
    }
}

// MARK: - Typing Indicator View
struct TypingIndicatorView: View {
    let text: String
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .opacity(animationPhase == index ? 1.0 : 0.4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                animationPhase = 2
            }
        }
    }
}

// Corrected Keyboard Publisher
#if canImport(UIKit)
extension Publishers {
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { notification in
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
            }
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }
        return Publishers.Merge(willShow, willHide).eraseToAnyPublisher()
    }
}
#endif
