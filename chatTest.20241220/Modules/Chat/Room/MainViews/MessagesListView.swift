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
    @State private var lastMessageCount = 0

    private var currentUserId: String {
        UserDefaults.standard.string(forKey: "userId") ?? ""
    }

    var body: some View {
        ZStack {
            // 1. THE MAIN SCROLLVIEW
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
            
            // 2. DIMMING OVERLAY (Only visible when double-tap reaction picker is active)
            if activeReactionPickerMessageId != nil {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.smooth(duration: 0.2)) {
                            activeReactionPickerMessageId = nil
                        }
                    }
                    .transition(.opacity)
                    .zIndex(500)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            scrollDownButton
        }
        .onChange(of: viewModel.messages.count) { oldCount, newCount in
            // Auto-scroll when new message is added (not when loading older messages)
            if newCount > oldCount && newCount > lastMessageCount {
                // Check if the newest message is from current user OR if we're already near bottom
                if let lastMessage = viewModel.messages.last,
                   lastMessage.senderId == currentUserId || !showScrollToBottom {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom = true
                    }
                }
            }
            lastMessageCount = newCount
        }
        .onAppear {
            lastMessageCount = viewModel.messages.count
        }
    }

    private var messagesContent: some View {
        LazyVStack(spacing: 8) {
            // Top Padding / Loading Indicator
            Color.clear
                .frame(height: verticalSizeClass == .compact ? 80 : 120)
                .overlay(alignment: .bottom) {
                    if viewModel.isFetchingOlderMessages {
                        ProgressView().controlSize(.small).padding(.bottom, 8)
                    }
                }

            ForEach(viewModel.messages) { message in
                let isActive = activeReactionPickerMessageId == message.id
                
                MessageRow(
                    message: message,
                    currentUserId: currentUserId,
                    isCurrentUser: message.senderId == currentUserId,
                    onImageTapped: onImageTapped,
                    onDelete: { Task { await viewModel.deleteMessage(message.id) } },
                    isReactionPickerActive: isActive,
                    onRequestReactionPicker: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            activeReactionPickerMessageId = (activeReactionPickerMessageId == message.id) ? nil : message.id
                        }
                    },
                    imageZoomNamespace: imageZoomNamespace
                )
                // IMPORTANT: This zIndex hoists the entire row (bubble + picker)
                // above the dimming layer (which is at zIndex 500)
                .zIndex(isActive ? 1000 : 1)
            }

            if let typingText = viewModel.typingText {
                TypingIndicatorView(text: typingText)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            // Bottom buffer for floating input area
            Color.clear.frame(height: verticalSizeClass == .compact ? 60 : 80)
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
