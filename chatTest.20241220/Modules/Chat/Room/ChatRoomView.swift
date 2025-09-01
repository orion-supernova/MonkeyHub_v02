import CloudKit
import SwiftUI

struct ChatRoomView: View {
    let room: ChatRoom
    @StateObject private var viewModel: ChatRoomViewModel
    @State private var messageText = ""
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isShowingAttachmentOptions = false
    @StateObject private var navigationState = NavigationStateManager.shared
    @State private var isLoading = true
    @State private var keyboardHeight: CGFloat = 0
    @State private var selectedImageUrl: URL?

    init(room: ChatRoom) {
        self.room = room
        self._viewModel = StateObject(wrappedValue: ChatRoomViewModel(roomId: room.id))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                MessagesListView(
                    viewModel: viewModel,
                    isLoading: isLoading,
                    onImageTapped: { url in
                        selectedImageUrl = url
                    }
                )

                Divider()

                MessageInputView(
                    messageText: $messageText,
                    showImagePicker: $showImagePicker,
                    isShowingAttachmentOptions: $isShowingAttachmentOptions,
                    onSendMessage: {
                        await viewModel.sendMessage(messageText)
                        messageText = ""
                    }
                )
            }
            .padding(.bottom, keyboardHeight)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Token") {
                    let token = getDeviceToken()
                    print("Device Token: \(token)")
                    UIPasteboard.general.string = token  // Copy to clipboard

                    // Optional: Show an alert that token was copied
                    let alertMessage =
                        token == "Token not available"
                        ? "No token available yet" : "Token copied to clipboard"

                    AlertManager.shared.showAlert(
                        title: "Device Token",
                        message: alertMessage
                    )
                }
            }
        }
        .navigationTitle(room.name)
        .task {
            await viewModel.loadMessages()
            isLoading = false
        }
        .onAppear {
            navigationState.currentScreen = .chatRoom
            setupKeyboardObservers()
        }
        .onDisappear {
            navigationState.currentScreen = .home
            removeKeyboardObservers()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .onChange(of: selectedImage) { newImage in
            if let image = newImage {
                Task {
                    await viewModel.sendImage(image)
                    selectedImage = nil
                }
            }
        }
        .animation(.easeOut, value: keyboardHeight)
        .fullScreenCover(item: $selectedImageUrl) { url in
            FullscreenImageView(url: url)
        }
    }

    private func getDeviceToken() -> String {
        return UserDefaults.standard.string(forKey: "deviceToken") ?? "Token not available"
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

                withAnimation(.easeOut(duration: duration)) {
                    keyboardHeight = keyboardFrame.height
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
                keyboardHeight = 0
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

#Preview {
    NavigationView {
        ChatRoomView(
            room: ChatRoom(
                name: "Test Room",
                createdBy: "test-user"
            )
        )
    }
}
