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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Token") {
                    let token = getDeviceToken()
                    print("Device Token: \(token)")
                    UIPasteboard.general.string = token // Copy to clipboard
                    
                    // Optional: Show an alert that token was copied
                    let alertMessage = token == "Token not available" ?
                        "No token available yet" : "Token copied to clipboard"
                    
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

    // Helper function to dismiss keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var messagesList: some View {
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
                    // Display messages in chronological order (oldest first, newest last)
                    ForEach(viewModel.messages.sorted(by: { $0.timestamp < $1.timestamp })) {
                        message in
                        MessageView(message: message)
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .onTapGesture {
            hideKeyboard()
        }
    }
    
    private func getDeviceToken() -> String {
        return UserDefaults.standard.string(forKey: "deviceToken") ?? "Token not available"
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
