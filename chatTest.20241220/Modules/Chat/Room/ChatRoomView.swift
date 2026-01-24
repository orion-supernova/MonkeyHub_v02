import CloudKit
import SwiftUI

struct ChatRoomView: View {
    @Environment(\.dismiss) private var dismiss
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
    @Namespace private var imageZoomNamespace
    @State private var roomAvatarImage: PlatformImage?

    init(room: ChatRoom) {
        self.room = room
        self._viewModel = StateObject(wrappedValue: ChatRoomViewModel(roomId: room.id))
    }
    
    var body: some View {
        ZStack {
            // 1. Full Screen Background
            LinearGradient(
                colors: selectedTheme.colors(for: colorScheme).sheetGradient + [selectedTheme.colors(for: colorScheme).background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .onTapGesture {
                #if canImport(UIKit)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }
            
            // 2. Loading / Empty State Layer
            if isLoading && viewModel.messages.isEmpty {
                ProgressView("Loading messages...")
                    .padding()
                    .modifier(LiquidGlassModifier(cornerRadius: 12))
                    .zIndex(1)
            } else if viewModel.messages.isEmpty {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "bubble.left",
                    description: Text("Start the conversation by sending a message")
                )
                .foregroundStyle(.secondary)
                .zIndex(1)
            }

            // 3. The Main Content Layer
            MessagesListView(
                viewModel: viewModel,
                isLoading: isLoading,
                onImageTapped: { url in
                    navigationState.path.append(url)
                },
                imageZoomNamespace: imageZoomNamespace
            )
            // Allows messages to scroll behind the top/bottom pebbles
            .ignoresSafeArea(.container, edges: .vertical)
            
            // --- TOP FLOATING PEBBLES ---
            .safeAreaInset(edge: .top) {
                HStack {
                    LiquidButton(icon: "chevron.left") {
                        dismiss()
                    }

                    Spacer()

                    RoomTitleView(title: room.name, avatarImage: roomAvatarImage)

                    Spacer()

                    LiquidButton(icon: "info.circle") {
                        showRoomInfo = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 5)
                .background(Color.clear)
            }
            
            // --- BOTTOM FLOATING INPUT ---
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    // Syncing indicator above input field
                    if viewModel.isFetchingNewMessages {
                        SyncingIndicatorView()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    MessageInputView(
                        messageText: $messageText,
                        showImagePicker: $showImagePicker,
                        isShowingAttachmentMenu: $isShowingAttachmentMenu,
                        onSendMessage: { text in
                            Task {
                                await viewModel.sendMessage(text)
                                await MainActor.run { messageText = "" }
                            }
                        },
                        onTextChanged: { text in viewModel.onTextChanged(text) },
                        onTakePhoto: { isShowingAttachmentMenu = false; showCamera = true },
                        onTakeVideo: { isShowingAttachmentMenu = false; showCamera = true },
                        onRecordAudio: { isShowingAttachmentMenu = false; showVoiceRecorder = true }
                    )
                }
                .padding(.bottom, 8)
                .background(Color.clear)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isFetchingNewMessages)
            }
        }
        // FIXED: Conditional compilation for cross-platform support
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .navigationTitle("")
        .navigationBarBackButtonHidden()
        #endif
        .task {
            await viewModel.loadMessages()
            isLoading = false
        }
        .onAppear {
            navigationState.currentScreen = .chatRoom
            navigationState.currentRoomId = room.id
            loadRoomAvatar()
        }
        .onDisappear {
            navigationState.currentScreen = .home
            navigationState.currentRoomId = nil
        }
        .fullScreenCover(isPresented: $showRoomInfo) {
            RoomInfoView(room: room)
        }
        .navigationDestination(for: URL.self) { url in
            FullscreenImageView(url: url)
                .navigationTransition(.zoom(sourceID: url, in: imageZoomNamespace))
        }
        // ... (The rest of your fullScreenCover and sheet logic stays here)
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showCamera) {
            CameraEditorView(isPresented: $showCamera) { image in
                Task {
                    isShowingAttachmentMenu = false
                    if let platformImage = image as? PlatformImage { await viewModel.sendImage(platformImage) }
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
            CameraEditorView(isPresented: $showCamera) { _ in isShowingAttachmentMenu = false }
        }
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceRecorderView(isPresented: $showVoiceRecorder) { _ in isShowingAttachmentMenu = false }
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
        .sheet(isPresented: $showImagePicker) { ImagePicker(image: $selectedImage) }
        .overlay(
            CustomBottomSheet(
                isPresented: $isShowingAttachmentMenu,
                background: selectedTheme.colors(for: colorScheme).background,
                cornerRadius: 20
            ) {
                AttachmentMenuView(
                    isPresented: $isShowingAttachmentMenu,
                    onTakePhoto: { showCamera = true },
                    onTakeVideo: { showCamera = true },
                    onRecordAudio: { showVoiceRecorder = true },
                    onChooseFromGallery: { showImagePicker = true }
                )
            }
        )
    }

    private func loadRoomAvatar() {
        // Try persisted avatarURL first (resolving filename to current session's path)
        if let avatarURL = room.avatarURL {
            let filename = avatarURL.lastPathComponent
            if let resolvedURL = AssetPersistenceService.shared.getURL(for: filename),
               let data = try? Data(contentsOf: resolvedURL),
               let image = PlatformImage.fromData(data) {
                roomAvatarImage = image
            }
        }
    }
}

struct RoomTitleView: View {
    let title: String
    let avatarImage: PlatformImage?

    @State private var isExpanded = false
    @State private var textLayoutWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    init(title: String, avatarImage: PlatformImage? = nil) {
        self.title = title
        self.avatarImage = avatarImage
    }

    var body: some View {
        HStack(spacing: avatarImage != nil ? 10 : 0) {
            // Avatar - only shown if image exists
            if let avatar = avatarImage {
                Image(platformImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    )
            }

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(isExpanded ? nil : 1)
        }
        .padding(.leading, avatarImage != nil ? 6 : 20)
        .padding(.trailing, 20)
        .padding(.vertical, isExpanded ? 8 : 0)
        .frame(minHeight: 44)
        .frame(height: isExpanded ? nil : 44)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in containerWidth = newValue }
            }
        )
        .background(
            Text(title)
                .font(.headline)
                .fixedSize()
                .padding(.horizontal, 20)
                .hidden()
                .overlay(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { textLayoutWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, newValue in textLayoutWidth = newValue }
                    }
                )
        )
        .modifier(LiquidGlassModifier(cornerRadius: 22))
        .onTapGesture {
            // Heuristic: If text is wider than container, it's truncated
            if textLayoutWidth > containerWidth {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isExpanded = true
                }

                // Auto-collapse after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        isExpanded = false
                    }
                }
            }
        }
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
