import SwiftUI
import Combine

struct MessagesListView: View {
    let viewModel: ChatRoomViewModel
    let isLoading: Bool
    let onImageTapped: (URL) -> Void
    @State private var activeReactionPickerMessageId: String?
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // No more rotation here!
                LazyVStack(spacing: 8) {
                    // Adaptive top spacer based on orientation
                    Spacer().frame(height: verticalSizeClass == .compact ? 80 : 120)

                    // Pagination Loader now at the top of the array
                    if viewModel.isFetchingOlderMessages {
                        ProgressView()
                            .padding()
                    }

                    // Normal order: oldest to newest
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
                            )
                        )
                        .padding(.horizontal)
                        .id(message.id)
                        .onAppear {
                            // Pagination logic: If we are not rotated,
                            // "Older" messages are at the top of the array (index 0)
                            if let first = viewModel.messages.first, first.id == message.id {
                                Task { await viewModel.loadOlderMessages() }
                            }
                        }
                    }

                    // Typing Indicator at the visual bottom
                    if let typingText = viewModel.typingText {
                        TypingIndicatorView(text: typingText)
                            .padding(.horizontal)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Adaptive bottom buffer (for floating input area)
                    Spacer().frame(height: verticalSizeClass == .compact ? 70 : 100)
                    
                    // Invisible anchor for rotation scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
            }
            // KEY: This tells the ScrollView to pin to the bottom by default
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
                            // Handle rotation: Scroll to bottom when view size changes
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                        }
                }
            )
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
