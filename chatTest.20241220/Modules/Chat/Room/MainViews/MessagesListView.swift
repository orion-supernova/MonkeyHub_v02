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
                VStack(spacing: 8) {
                    if isLoading && viewModel.messages.isEmpty {
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
                        ForEach(viewModel.messages.sorted(by: { $0.timestamp < $1.timestamp })) { message in
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
                        
                        // Footer spacer for comfortable scrolling
                        Color.clear
                            .frame(height: 20)
                            .id("bottomSpacer")
                    }
                }
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.interactively) // Native keyboard handling
            .onAppear {
                self.proxy = proxy
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: isLoading) { newValue in
                if !newValue {
                    scrollToBottom(proxy, animated: false)
                }
            }
            .onChange(of: viewModel.messages) { newValue in
                 scrollToBottom(proxy, animated: true)
            }
            .onChange(of: viewModel.messages.count) { _ in
                 scrollToBottom(proxy, animated: true)
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.spring(duration: 0.3)) {
                proxy.scrollTo("bottomSpacer", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottomSpacer", anchor: .bottom)
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
}
