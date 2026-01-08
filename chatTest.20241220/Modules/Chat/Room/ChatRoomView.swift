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
    @State private var selectedImageUrl: URL?
    @State private var showCamera = false
    @State private var showVoiceRecorder = false
    @State private var isShowingAttachmentMenu = false

    init(room: ChatRoom) {
        self.room = room
        self._viewModel = StateObject(wrappedValue: ChatRoomViewModel(roomId: room.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            MessagesListView(
                viewModel: viewModel,
                isLoading: isLoading,
                onImageTapped: { url in
                    selectedImageUrl = url
                }
            )

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
        .navigationTitle(room.name)
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
        .task {
            await viewModel.loadMessages()
            isLoading = false
        }
        .onAppear {
            navigationState.currentScreen = .chatRoom
            navigationState.currentRoomId = room.id  // Track active room for notification suppression
        }
        .onDisappear {
            navigationState.currentScreen = .home
            navigationState.currentRoomId = nil  // Clear active room
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
