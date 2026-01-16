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
    @State private var scrollPosition: String? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Adaptive top spacer based on orientation
                    Spacer()
                        .frame(height: verticalSizeClass == .compact ? 80 : 120)
                        .id("top-spacer")
                        .overlay(alignment: .bottom) {
                            if viewModel.isFetchingOlderMessages {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.bottom, 8)
                            }
                        }
                    
                    // Invisible trigger for loading older messages
                    // Only triggers when the user scrolls PAST the top message
                    Color.clear
                        .frame(height: 20)
                        .id("top-load-trigger")
                        .onAppear {
                            if !viewModel.isFetchingOlderMessages, let firstMessageId = viewModel.messages.first?.id {
                                // Anchor to the current top message to prevent jumping to the new top
                                scrollPosition = firstMessageId
                                Task { await viewModel.loadOlderMessages() }
                            }
                        }

                    ForEach(viewModel.messages) { message in
                        MessageView(
                            message: message,
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
                        .id(message.id)
                    }

                    if let typingText = viewModel.typingText {
                        TypingIndicatorView(text: typingText)
                            .padding(.horizontal)
                            .id("typingIndicator")
                    }

                    // Adaptive bottom buffer (for floating input area)
                    Spacer().frame(height: verticalSizeClass == .compact ? 70 : 100)
                    
                    // Anchor for scroll-to-bottom logic
                    Color.clear
                        .frame(height: 2)
                        .id("bottom")
                        .onAppear { showScrollToBottom = false }
                        .onDisappear { showScrollToBottom = true }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollPosition)
            .defaultScrollAnchor(.bottom)
            .background(Color.clear)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                activeReactionPickerMessageId = nil
                #if canImport(UIKit)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size) { _, _ in
                            // Still need this for rotation, but use simple animation
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                scrollPosition = "bottom"
                            }
                        }
                }
            )
            .overlay(alignment: .bottomTrailing) {
                if showScrollToBottom {
                    Button {
                        // scrollPosition binding is more robust against momentum
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            scrollPosition = "bottom"
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, height: 38)
                            .modifier(LiquidGlassModifier(cornerRadius: 19))
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 100)
                    .transition(.opacity) // Pure fade in/out
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showScrollToBottom)
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
