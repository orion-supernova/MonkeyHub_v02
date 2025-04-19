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

    init(room: ChatRoom) {
        self.room = room
        self._viewModel = StateObject(wrappedValue: ChatRoomViewModel(roomId: room.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesList

            Divider()

            messageInputView
        }
        .navigationTitle(room.name)
        .task {
            await viewModel.loadMessages()
        }
        .onAppear {
            navigationState.currentScreen = .chatRoom
        }
        .onDisappear {
            navigationState.currentScreen = .home
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
    }

    private var messagesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if viewModel.messages.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "bubble.left",
                        description: Text("Start the conversation by sending a message")
                    )
                    .padding()
                } else {
                    ForEach(viewModel.messages) { message in
                        MessageView(message: message)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private var messageInputView: some View {
        HStack(spacing: 8) {
            Button {
                isShowingAttachmentOptions.toggle()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .confirmationDialog("Add Attachment", isPresented: $isShowingAttachmentOptions) {
                Button("Photo") {
                    showImagePicker = true
                }
                Button("Cancel", role: .cancel) {}
            }

            TextField("Message", text: $messageText)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    await viewModel.sendMessage(messageText)
                    messageText = ""
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
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
