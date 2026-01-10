import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
#endif

struct MessagesListView: View {
    let viewModel: ChatRoomViewModel
    let isLoading: Bool
    let onImageTapped: (URL) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.messages) { message in
                    MessageView(
                        message: message,
                        onImageTapped: onImageTapped,
                        onDelete: {
                            Task {
                                await viewModel.deleteMessage(message.id)
                            }
                        }
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
            #if canImport(UIKit)
            hideKeyboard()
            #endif
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

