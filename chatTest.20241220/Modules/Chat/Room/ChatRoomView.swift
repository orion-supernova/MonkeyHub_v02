import CloudKit
import SwiftUI

struct ChatRoomView: View {
    let room: ChatRoom
    @StateObject private var viewModel: ChatRoomViewModel
    @State private var messageText = ""
    @State private var showImagePicker = false
    @State private var selectedImage: PlatformImage?
    @State private var isShowingAttachmentOptions = false
    @StateObject private var navigationState = NavigationStateManager.shared
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @State private var isLoading = true
    @State private var selectedImageUrl: URL?
    @State private var showCamera = false
    @State private var showVoiceRecorder = false
    @State private var isShowingAttachmentMenu = false
    @State private var showRoomInfo = false

    init(room: ChatRoom) {
        self.room = room
        self._viewModel = StateObject(wrappedValue: ChatRoomViewModel(roomId: room.id))
    }

    var body: some View {
        ZStack {
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
                        let textToSend = messageText
                        messageText = ""
                        await viewModel.sendMessage(textToSend)
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
            .background(Color.platformBackground)

            if isLoading && viewModel.messages.isEmpty {
                ProgressView("Loading messages...")
                    .padding()
                    .background(Color.secondarySystemGroupedBackground)
                    .cornerRadius(10)
            } else if viewModel.messages.isEmpty {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "bubble.left",
                    description: Text("Start the conversation by sending a message")
                )
            }
        }
        .navigationTitle(room.name)
        .toolbar {
            ToolbarItem(placement: {
                #if canImport(UIKit)
                return .navigationBarTrailing
                #else
                return .automatic
                #endif
            }()) {
                Button {
                    showRoomInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                }
            }
        }
        .task {
            await viewModel.loadMessages()
            isLoading = false
        }
        .onAppear {
            navigationState.currentScreen = .chatRoom
            navigationState.currentRoomId = room.id
        }
        .onDisappear {
            navigationState.currentScreen = .home
            navigationState.currentRoomId = nil
        }
        .sheet(isPresented: $showRoomInfo) {
            // onDismiss callback - refresh messages when sheet closes
            Task {
                await viewModel.loadMessages()
            }
        } content: {
            RoomInfoView(room: room)
        }
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showCamera) {
            CameraEditorView(isPresented: $showCamera) { image in
                Task {
                    isShowingAttachmentMenu = false
                    if let platformImage = image as? PlatformImage {
                        await viewModel.sendImage(platformImage)
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
        #else
        .sheet(isPresented: $showCamera) {
            CameraEditorView(isPresented: $showCamera) { image in
                Task {
                    isShowingAttachmentMenu = false
                }
            }
        }
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceRecorderView(isPresented: $showVoiceRecorder) { url in
                Task {
                    isShowingAttachmentMenu = false
                }
            }
        }
        #endif
        .onChange(of: selectedImage) { newImage in
            if let image = newImage {
                Task {
                    isShowingAttachmentMenu = false
                    await viewModel.sendImage(image)
                    selectedImage = nil
                }
            }
        }
        #if canImport(UIKit)
        .fullScreenCover(item: $selectedImageUrl) { url in
            FullscreenImageView(url: url)
        }
        #else
        .sheet(item: $selectedImageUrl) { url in
            FullscreenImageView(url: url)
        }
        #endif
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