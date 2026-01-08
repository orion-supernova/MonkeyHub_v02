import SwiftUI

struct MessagesListView: View {
    let viewModel: ChatRoomViewModel
    let isLoading: Bool
    let onImageTapped: (URL) -> Void
    @State private var proxy: ScrollViewProxy?

    private var lastMessageId: String? {
        return viewModel.messages.sorted(by: { $0.timestamp < $1.timestamp }).last?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if isLoading {
                        Spacer()
                        ProgressView("Loading messages...")
                            .padding()
                        Spacer()
                    } else if viewModel.messages.isEmpty {
                        ContentUnavailableView(
                            "No Messages",
                            systemImage: "bubble.left",
                            description: Text("Start the conversation by sending a message")
                        )
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach(viewModel.messages.sorted(by: { $0.timestamp < $1.timestamp }))
                        {
                            message in
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
                        }
                    }
                }
                .padding(.vertical)
            }
            .onAppear {
                self.proxy = proxy
                setupKeyboardObservers()
                scrollToBottom(proxy)
            }
            .onDisappear {
                removeKeyboardObservers()
            }
            .onChange(of: isLoading) { newValue in
                if !newValue {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: viewModel.messages) { newValue in
                 scrollToBottom(proxy)
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastMessage = viewModel.messages.sorted(by: { $0.timestamp < $1.timestamp }).last else { return }

        withAnimation(.spring(duration: 0.3)) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { _ in
            guard let proxy else { return }
            // Small delay to allow keyboard height change to affect ScrollView
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToBottom(proxy)
            }
        }
    }

    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillShowNotification, object: nil)
    }
}
