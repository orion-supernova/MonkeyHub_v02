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
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @State private var isLoading = true
    @State private var keyboardHeight: CGFloat = 0
    @State private var selectedImageUrl: URL?
    @State private var showCamera = false
    @State private var showVoiceRecorder = false
    @State private var isShowingAttachmentMenu = false

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
                    isShowingAttachmentMenu: $isShowingAttachmentMenu,
                    onSendMessage: {
                        await viewModel.sendMessage(messageText)
                        messageText = ""
                    },
                    onTakePhoto: {
                        isShowingAttachmentMenu = false
                        showCamera = true
                    },
                    onTakeVideo: {
                        isShowingAttachmentMenu = false
                        showCamera = true
                    },
                    onRecordAudio: {
                        isShowingAttachmentMenu = false
                        showVoiceRecorder = true
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(isPresented: $showCamera) { url, isVideo in
                Task {
                    if isVideo {
                        await viewModel.sendVideo(url)
                    } else {
                        await viewModel.sendImage(from: url)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showVoiceRecorder) {
            VoiceRecorderView(isPresented: $showVoiceRecorder) { url in
                Task {
                    isShowingAttachmentMenu = false
                    await viewModel.sendAudio(url)
                }
            }
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
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .overlay(
            CustomBottomSheet(
                isPresented: $isShowingAttachmentMenu,
                background: selectedTheme.colors(for: colorScheme).background,
                cornerRadius: 20
            ) {
                AttachmentMenuView(
                    isPresented: $isShowingAttachmentMenu,
                    onTakePhoto: {
                        showCamera = true
                    },
                    onTakeVideo: {
                        showCamera = true
                    },
                    onRecordAudio: {
                        showVoiceRecorder = true
                    },
                    onChooseFromGallery: {
                        showImagePicker = true
                    }
                )
            }
        )
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
