import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
#endif

struct MessagesListView: View {
    let viewModel: ChatRoomViewModel
    let isLoading: Bool
    let onImageTapped: (URL) -> Void
    @State private var activeReactionPickerMessageId: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Typing Indicator (at visual bottom, internal first)
                if let typingText = viewModel.typingText {
                    TypingIndicatorView(text: typingText)
                        .padding(.horizontal)
                        .rotationEffect(.degrees(180))
                        .transition(.opacity.combined(with: .scale))
                }
                
                ForEach(viewModel.messages) { message in
                    MessageView(
                        message: message,
                        onImageTapped: onImageTapped,
                        onDelete: {
                            Task {
                                await viewModel.deleteMessage(message.id)
                            }
                        },
                        showReactionPicker: Binding(
                            get: { activeReactionPickerMessageId == message.id },
                            set: { shouldShow in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    activeReactionPickerMessageId = shouldShow ? message.id : nil
                                }
                            }
                        )
                    )
                    .padding(.horizontal)
                    .id(message.id)
                    .rotationEffect(.degrees(180)) // Un-flip the message content
                    .onAppear {
                        // Trigger pagination when reaching the visual top (internal last element)
                        if let last = viewModel.messages.last, last.id == message.id {
                            Task {
                                await viewModel.loadOlderMessages()
                            }
                        }
                    }
                }

                // Pagination Loader (at the visual top, internal end)
                if viewModel.isFetchingOlderMessages {
                    ProgressView()
                        .padding()
                        .rotationEffect(.degrees(180))
                }
            }
            .padding(.vertical)
        }
        .rotationEffect(.degrees(180)) // Flip the entire scroll view
        .background(Color.primary.colorInvert()) // Simple platform-agnostic alternative to systemBackground
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            if activeReactionPickerMessageId != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activeReactionPickerMessageId = nil
                }
            } else {
                #if canImport(UIKit)
                hideKeyboard()
                #endif
            }
        }
    }

    #if canImport(UIKit)
    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
    #endif
}

// MARK: - Typing Indicator View

struct TypingIndicatorView: View {
    let text: String
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(spacing: 8) {
            // Animated dots
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .opacity(animationPhase == index ? 1.0 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .onAppear {
            withAnimation {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Keyboard Height Publisher
#if canImport(UIKit)
extension Publishers {
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { notification -> CGFloat in
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
            }

        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ -> CGFloat in 0 }

        return Publishers.Merge(willShow, willHide)
            .eraseToAnyPublisher()
    }
}
#endif