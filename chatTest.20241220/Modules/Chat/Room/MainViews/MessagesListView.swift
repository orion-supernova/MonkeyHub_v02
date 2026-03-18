import SwiftUI
import Combine

struct MessagesListView: View {
    let viewModel: ChatRoomViewModel
    let isLoading: Bool
    let onImageTapped: (URL) -> Void
    let imageZoomNamespace: Namespace.ID
    let topInset: CGFloat
    let bottomInset: CGFloat
    
    @State private var activeReactionPickerMessageId: String?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showScrollToBottom = false
    @State private var scrollToBottom = false

    private var currentUserId: String {
        UserDefaults.standard.string(forKey: "userId") ?? ""
    }

    var body: some View {
        ZStack {
            // 1. DIMMING LAYER — sits behind the scroll view,
            // visible through the scroll view's clear background.
            // This dims the background gradient WITHOUT covering the picker.
            if activeReactionPickerMessageId != nil {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // 2. THE MAIN SCROLLVIEW (always on top of dimming)
            UIKitScrollView(
                content: messagesContent,
                firstItemId: viewModel.messages.first?.id,
                itemCount: viewModel.messages.count,
                topInset: topInset,
                bottomInset: bottomInset,
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
            // When no messages, pass touches through so the empty state and
            // input bar behind this scroll view remain fully interactive.
            .allowsHitTesting(!viewModel.messages.isEmpty)
            .zIndex(1)
        }
        .overlay(alignment: .bottomTrailing) {
            scrollDownButton
        }
        .onAppear { }
    }

    private func dismissPicker() {
        withAnimation(.smooth(duration: 0.2)) {
            activeReactionPickerMessageId = nil
        }
    }

    private var messagesContent: some View {
        LazyVStack(spacing: 8) {
            Color.clear
                .frame(height: max(topInset, verticalSizeClass == .compact ? 20 : 45))
                .overlay(alignment: .bottom) {
                    if viewModel.isFetchingOlderMessages {
                        ProgressView().controlSize(.small).padding(.bottom, 8)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { dismissPicker() }

            ForEach(viewModel.messages) { message in
                let isActive = activeReactionPickerMessageId == message.id
                let pickerIsOpen = activeReactionPickerMessageId != nil

                MessageRow(
                    message: message,
                    currentUserId: currentUserId,
                    isCurrentUser: message.senderId == currentUserId,
                    onImageTapped: onImageTapped,
                    onDelete: { Task { await viewModel.deleteMessage(message.id) } },
                    onResend: { Task { await viewModel.sendMessage(message.content) } },
                    isReactionPickerActive: isActive,
                    onRequestReactionPicker: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            activeReactionPickerMessageId = (activeReactionPickerMessageId == message.id) ? nil : message.id
                        }
                    },
                    imageZoomNamespace: imageZoomNamespace
                )
                // Active row draws above non-active rows
                .zIndex(isActive ? 1000 : 1)
                // Fade non-active rows uniformly (no visible per-row rectangles)
                .opacity(pickerIsOpen && !isActive ? 0.4 : 1.0)
                // Invisible tap catcher to dismiss picker when tapping other rows
                .overlay {
                    if pickerIsOpen && !isActive {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { dismissPicker() }
                    }
                }
            }

            if let typingText = viewModel.typingText {
                TypingIndicatorView(text: typingText)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            // Small breathing room; structural clearance is handled by UIKitScrollView insets.
            Color.clear.frame(height: max(bottomInset, verticalSizeClass == .compact ? 16 : 60))
                .contentShape(Rectangle())
                .onTapGesture { dismissPicker() }
        }
    }

    private var scrollDownButton: some View {
        Button {
            scrollToBottom = true
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.1), radius: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 100)
        .opacity(showScrollToBottom ? 1 : 0)
        .scaleEffect(showScrollToBottom ? 1 : 0.5)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showScrollToBottom)
    }
}

// MARK: - Optimized Message Row
struct MessageRow: View, Equatable {
    let message: ChatMessage
    let currentUserId: String
    let isCurrentUser: Bool
    let onImageTapped: (URL) -> Void
    let onDelete: () -> Void
    let onResend: () -> Void
    let isReactionPickerActive: Bool
    let onRequestReactionPicker: () -> Void
    let imageZoomNamespace: Namespace.ID

    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.message.id == rhs.message.id &&
        lhs.message.status == rhs.message.status &&
        lhs.message.reactions.count == rhs.message.reactions.count &&
        lhs.isReactionPickerActive == rhs.isReactionPickerActive
    }

    var body: some View {
        MessageView(
            message: message,
            currentUserId: currentUserId,
            isCurrentUser: isCurrentUser,
            onImageTapped: onImageTapped,
            onDelete: onDelete,
            onRequestReactionPicker: onRequestReactionPicker,
            isReactionPickerActive: isReactionPickerActive,
            onResend: onResend,
            imageZoomNamespace: imageZoomNamespace
        )
        .id(message.id)
        .padding(.horizontal)
    }
}

// MARK: - Typing Indicator View (Fixed Animation)
struct TypingIndicatorView: View {
    let text: String
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(isAnimating ? 1.0 : 0.5)
                        .opacity(isAnimating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Syncing Indicator View (Loading new messages)
struct SyncingIndicatorView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Syncing...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
