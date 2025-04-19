import SwiftUI

struct MessagesListView: View {
    let viewModel: ChatRoomViewModel
    let isLoading: Bool
    @State private var proxy: ScrollViewProxy?

    private var lastMessageId: String? {
        return viewModel.messages.sorted(by: { $0.timestamp < $1.timestamp }).last?.id
    }

    var body: some View {
        GeometryReader { geometry in
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
                        } else {
                            ForEach(viewModel.messages.sorted(by: { $0.timestamp < $1.timestamp }))
                            {
                                message in
                                MessageView(message: message)
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
                }
                .onDisappear {
                    removeKeyboardObservers()
                }
                .onChange(of: isLoading) { newValue in
                    if !newValue {
                        scrollToBottom(proxy)
                    }
                }
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let id = viewModel.messages.first?.id else { return }

        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        guard let proxy else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                scrollToBottom(proxy)
            }
        }
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect
            {
                let duration =
                    notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
                    as? Double ?? 0.25

                guard let proxy else { return }
                withAnimation(.easeOut(duration: duration)) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollToBottom(proxy)
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
        ) { notification in
            let duration =
                notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
                ?? 0.25

            withAnimation(.easeOut(duration: duration)) {
            }
        }
    }

    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
}
