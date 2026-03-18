import SwiftUI
#if canImport(UIKit)
import UIKit
#endif


struct ChatRoomView: View {
    @Environment(\.dismiss) private var dismiss
    let room: ChatRoom
    @ObservedObject private var repository = ChatRepository.shared
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
    @State private var isUserMember = true  // Assume member until checked
    @State private var showRoomDeletedAlert = false
    @State private var showRemovedFromRoomAlert = false
    @State private var topChromeHeight: CGFloat = 0
    @State private var bottomChromeHeight: CGFloat = 0

    #if canImport(UIKit)
    @State private var screenshotObserver: NSObjectProtocol?
    #endif

    // Keyboard navigation (macOS) — nil means text field cursor mode
    @State private var navIndex: Int? = nil
    @FocusState private var isNavActive: Bool

    /// Live room data from the repository subscription — falls back to the initial room.
    private var liveRoom: ChatRoom {
        repository.rooms.first { $0.id == room.id } ?? room
    }

    init(room: ChatRoom) {
        self.room = room
        self._viewModel = StateObject(wrappedValue: ChatRoomViewModel(roomId: room.id))
    }
    
    var body: some View {
        GeometryReader { proxy in
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
            } else if viewModel.messages.isEmpty {
                if liveRoom.type == .secret {
                    ChamberOfSecretsWelcomeView(messageLifetime: liveRoom.messageLifetime)
                } else {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "bubble.left",
                        description: Text("Start the conversation by sending a message")
                    )
                    .foregroundStyle(.secondary)
                }
            }

            // 3. The Main Content Layer
            messagesListContent
        }
        .overlay(alignment: .top) {
            topControls
        }
        .overlay(alignment: .bottom) {
            bottomControls
        }
        .onPreferenceChange(TopChromeHeightPreferenceKey.self) { topChromeHeight = $0 }
        .onPreferenceChange(BottomChromeHeightPreferenceKey.self) { bottomChromeHeight = $0 }
        // FIXED: Conditional compilation for cross-platform support
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .navigationTitle("")
        .navigationBarBackButtonHidden()
        .focusable()
        .focused($isNavActive)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            guard navIndex != nil else { return }
            let row = navIndex! / 3
            let col = navIndex! % 3
            switch direction {
            case .left:
                if col > 0 { navIndex = row * 3 + (col - 1) }
            case .right:
                if col < 2 { navIndex = row * 3 + (col + 1) }
            case .up:
                if row > 0 { navIndex = (row - 1) * 3 + col }
            case .down:
                if row < 1 { navIndex = (row + 1) * 3 + col }
            @unknown default:
                break
            }
        }
        .onKeyPress(.return) {
            guard let idx = navIndex else { return .ignored }
            activateNavElement(idx)
            return .handled
        }
        .onExitCommand {
            if navIndex != nil {
                dismiss()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ChatRoomEnterNavMode"))) { _ in
            navIndex = 4
            isNavActive = true
        }
        #endif
        .task(id: liveRoom.avatarStorageId) {
            roomAvatarImage = nil
            if let storageId = liveRoom.avatarStorageId {
                // Realtime-safe: same storageId reads from cache, changed storageId refetches.
                if let image = await ConvexFileCacheService.shared.image(for: storageId) {
                    roomAvatarImage = image
                }
            } else {
                // Fallback: try persisted avatarURL from local disk
                loadRoomAvatar()
            }
        }
        .task {
            // Check if user is still a member of this room
            await checkMembership()
            await viewModel.loadMessages()
            isLoading = false
        }
        .onAppear {
            navigationState.currentScreen = .chatRoom
            navigationState.currentRoomId = room.id
            #if canImport(UIKit)
            if liveRoom.type == .secret {
                screenshotObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.userDidTakeScreenshotNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    AlertManager.shared.showAlert(
                        title: "Screenshot Detected",
                        message: "Screenshots are not allowed in Chamber of Secrets rooms."
                    )
                }
            }
            #endif
        }
        .onDisappear {
            navigationState.currentScreen = .home
            navigationState.currentRoomId = nil
            #if canImport(UIKit)
            if let observer = screenshotObserver {
                NotificationCenter.default.removeObserver(observer)
                screenshotObserver = nil
            }
            #endif
        }
        // Listen for real-time room deletion notifications
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RoomWasDeleted"))) { notification in
            if let roomId = notification.userInfo?["roomId"] as? String, roomId == room.id {
                showRoomDeletedAlert = true
            }
        }
        // Listen for real-time removal from room notifications
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserRemovedFromRoom"))) { notification in
            if let roomId = notification.userInfo?["roomId"] as? String, roomId == room.id {
                withAnimation {
                    isUserMember = false
                }
                showRemovedFromRoomAlert = true
            }
        }
        .alert("Room Deleted", isPresented: $showRoomDeletedAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("This room has been deleted by another user.")
        }
        .alert("Removed from Room", isPresented: $showRemovedFromRoomAlert) {
            Button("OK") {
                // Stay in the room to view history, but can't send messages
            }
            Button("Leave") {
                dismiss()
            }
        } message: {
            Text("You have been removed from this room. You can still view message history but cannot send new messages.")
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showRoomInfo) {
            RoomInfoView(room: liveRoom)
        }
        .navigationDestination(for: URL.self) { url in
            FullscreenImageView(url: url)
                .navigationTransition(.zoom(sourceID: url, in: imageZoomNamespace))
        }
        #else
        .sheet(isPresented: $showRoomInfo) {
            RoomInfoView(room: liveRoom)
        }
        .navigationDestination(for: URL.self) { url in
            FullscreenImageView(url: url)
        }
        #endif
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
    }

    // MARK: - Messages List

    @ViewBuilder
    private var messagesListContent: some View {
        MessagesListView(
            viewModel: viewModel,
            isLoading: isLoading,
            onImageTapped: { url in
                navigationState.path.append(url)
            },
            imageZoomNamespace: imageZoomNamespace,
            topInset: topChromeHeight,
            bottomInset: bottomChromeHeight + 20
        )
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 8) {
            if isUserMember {
                if viewModel.isFetchingNewMessages {
                    SyncingIndicatorView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                MessageInputView(
                    messageText: $messageText,
                    showImagePicker: $showImagePicker,
                    isShowingAttachmentMenu: $isShowingAttachmentMenu,
                    navHighlight: navIndex,
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
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "person.slash.fill")
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).destructive)
                    Text("You are no longer a member of this room")
                        .font(.subheadline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                )
                .padding(.horizontal, 16)
            }
        }
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isFetchingNewMessages)
        .background(
            GeometryReader { chromeProxy in
                Color.clear
                    .preference(key: BottomChromeHeightPreferenceKey.self, value: chromeProxy.size.height)
            }
        )
    }

    private var topControls: some View {
        HStack {
            LiquidButton(icon: "chevron.left", showFocusRing: navIndex == 0) {
                dismiss()
            }

            Spacer()

            RoomTitleView(
                title: liveRoom.name,
                roomType: liveRoom.type,
                avatarImage: roomAvatarImage,
                showFocusRing: navIndex == 1
            )

            Spacer()

            LiquidButton(icon: "info.circle", showFocusRing: navIndex == 2) {
                showRoomInfo = true
            }
        }
        .padding(.horizontal, 16)
        .background(Color.clear)
        .background(
            GeometryReader { chromeProxy in
                Color.clear
                    .preference(key: TopChromeHeightPreferenceKey.self, value: chromeProxy.size.height + 12)
            }
        )
    }

    /// Check if current user is still a member of this room
    private func checkMembership() async {
        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""

        do {
            // Fetch the latest room data from Convex
            if let latestRoom = try await ConvexChatAPI.shared.fetchRoom(roomId: room.id) {
                isUserMember = latestRoom.participants.contains(userId)
                if !isUserMember {
                    print("⚠️ User is no longer a member of room: \(room.name)")
                }
            } else {
                // Room doesn't exist anymore
                isUserMember = false
                print("⚠️ Room no longer exists: \(room.id)")
            }
        } catch {
            // On error, assume still a member (fail open for better UX)
            print("⚠️ Failed to check membership: \(error)")
            isUserMember = true
        }
    }

    #if os(macOS)
    private func activateNavElement(_ index: Int) {
        switch index {
        case 0: dismiss()
        case 1: break // room title
        case 2: showRoomInfo = true
        case 3: isShowingAttachmentMenu.toggle()
        case 4:
            // Re-enter text field cursor mode
            navIndex = nil
            isNavActive = false
            // Delay to let focus change complete before refocusing text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: NSNotification.Name("ChatRoomFocusTextField"), object: nil)
            }
        case 5:
            // Send message
            let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let textToSend = messageText
                messageText = ""
                Task { await viewModel.sendMessage(textToSend) }
            }
        default: break
        }
    }
    #endif

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

// MARK: - Chamber of Secrets Welcome View

struct ChamberOfSecretsWelcomeView: View {
    let messageLifetime: TimeInterval?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Big icon
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color.orange.opacity(0.3), Color.red.opacity(0.1), Color.clear],
                            center: .center, startRadius: 10, endRadius: 80
                        ))
                        .frame(width: 160, height: 160)
                    Text("🔥")
                        .font(.system(size: 72))
                }

                // Title
                VStack(spacing: 8) {
                    Text("Chamber of Secrets")
                        .font(.title2.bold())
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                        )
                    Text("Messages in this room automatically delete after a set time — whether read or not.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Feature cards
                VStack(spacing: 12) {
                    featureRow(icon: "flame.fill", color: .orange,
                               title: "Auto-Deleting Messages",
                               subtitle: messageLifetime != nil ? "Every message deletes after \(formatLifetime(messageLifetime!))" : "Messages delete on a timer")
                    featureRow(icon: "exclamationmark.shield.fill", color: .red,
                               title: "Screenshot Detection",
                               subtitle: "You'll be notified if someone takes a screenshot")
                    featureRow(icon: "eye.slash.fill", color: .purple,
                               title: "No Message History",
                               subtitle: "Once gone, messages cannot be recovered")
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            #if canImport(UIKit)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
        }
    }

    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(color.opacity(0.2), lineWidth: 1))
    }
}

struct RoomTitleView: View {
    let title: String
    var roomType: RoomType = .regular
    let avatarImage: PlatformImage?

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    var showFocusRing: Bool = false
    @State private var isExpanded = false
    @State private var textLayoutWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    init(title: String, roomType: RoomType = .regular, avatarImage: PlatformImage? = nil, showFocusRing: Bool = false) {
        self.title = title
        self.roomType = roomType
        self.avatarImage = avatarImage
        self.showFocusRing = showFocusRing
    }

    var body: some View {
        HStack(spacing: 8) {
            // Avatar circle — only rendered when a real image exists
            if let avatar = avatarImage {
                Image(platformImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    // Thin background-coloured border gives the layered "sticker on top" look
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }

            // Chamber of Secrets flame icon
            if roomType == .secret {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .symbolEffect(.variableColor.cumulative, options: .repeat(.continuous))
            }

            // Room name
            Text(title)
                .font(.headline)
                .lineLimit(isExpanded ? nil : 1)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
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
                        .hidden()
                        .overlay(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { textLayoutWidth = proxy.size.width }
                                    .onChange(of: proxy.size.width) { _, newValue in textLayoutWidth = newValue }
                            }
                        )
                )
        }
        .padding(.leading, avatarImage != nil ? 6 : 16)
        .padding(.trailing, 16)
        .padding(.vertical, isExpanded ? 8 : 4)
        .frame(minHeight: 44)
        .frame(height: isExpanded ? nil : 44)
        .modifier(LiquidGlassModifier(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.5
                )
                .opacity(showFocusRing ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: showFocusRing)
        )
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

private struct TopChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct BottomChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
