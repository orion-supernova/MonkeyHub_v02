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
                onImageTapped: { url in selectedImageUrl = url }
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
                    
                    RoomTitleView(title: room.name)
                    
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
                .padding(.bottom, 8)
                .background(Color.clear)
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
        }
        .onDisappear {
            navigationState.currentScreen = .home
            navigationState.currentRoomId = nil
        }
        .sheet(isPresented: $showRoomInfo) {
            Task { await viewModel.loadMessages() }
        } content: {
            RoomInfoView(room: room)
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
        .fullScreenCover(item: $selectedImageUrl) { url in FullscreenImageView(url: url) }
        #else
        .sheet(isPresented: $showCamera) {
            CameraEditorView(isPresented: $showCamera) { _ in isShowingAttachmentMenu = false }
        }
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceRecorderView(isPresented: $showVoiceRecorder) { _ in isShowingAttachmentMenu = false }
        }
        .sheet(item: $selectedImageUrl) { url in FullscreenImageView(url: url) }
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
}

struct RoomTitleView: View {
    let title: String
    @State private var isExpanded = false
    @State private var textLayoutWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    var body: some View {
        Text(title)
            .font(.headline)
            .multilineTextAlignment(.center)
            .lineLimit(isExpanded ? nil : 1)
            .padding(.horizontal, 20)
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
