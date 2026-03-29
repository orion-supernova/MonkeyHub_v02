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
    @State private var screenCaptureObserver: NSObjectProtocol?
    #endif

    // Keyboard navigation (macOS) — nil means text field cursor mode
    @State private var navIndex: Int? = nil
    @FocusState private var isNavActive: Bool

    /// Live room data from the repository subscription — falls back to the initial room.
    public var liveRoom: ChatRoom {
        repository.rooms.first { $0.id == room.id } ?? room
    }

    init(room: ChatRoom) {
        self.room = room
        self._viewModel = StateObject(wrappedValue: ChatRoomViewModel(roomId: room.id))
    }
    
    var body: some View {
        GeometryReader { proxy in
        let effectiveBottomInset = bottomChromeHeight + 20
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
            messagesListContent(bottomInset: effectiveBottomInset)
        }
        .coordinateSpace(name: "ChatRoomSpace")
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
        .background(SwipeBackEnabler())
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
                    Task { @MainActor in
                        AlertManager.shared.showAlert(
                            title: "Screenshot Detected",
                            message: "Screenshots are not allowed in Chamber of Secrets rooms."
                        )
                    }
                }

                screenCaptureObserver = NotificationCenter.default.addObserver(
                    forName: UIScreen.capturedDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    guard UIScreen.main.isCaptured else { return }
                    Task { @MainActor in
                        AlertManager.shared.showAlert(
                            title: "Capture Blocked",
                            message: "Screen recording, mirroring, and broadcasts are blocked in Chamber of Secrets rooms."
                        )
                    }
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
            if let observer = screenCaptureObserver {
                NotificationCenter.default.removeObserver(observer)
                screenCaptureObserver = nil
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
        .sensitiveContentProtection(enabled: liveRoom.type == .secret)
        }
    }

    // MARK: - Messages List

    @ViewBuilder
    private func messagesListContent(bottomInset: CGFloat) -> some View {
        MessagesListView(
            viewModel: viewModel,
            isLoading: isLoading,
            onImageTapped: { url in
                navigationState.path.append(url)
            },
            imageZoomNamespace: imageZoomNamespace,
            topInset: topChromeHeight,
            bottomInset: bottomInset
        )
        .ignoresSafeArea(.all, edges: .bottom)
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
                        Task { await viewModel.sendMessage(text) }
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
                // Magical Glowing Icon
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors:[Color.green.opacity(0.4), Color.teal.opacity(0.1), Color.clear],
                            center: .center, startRadius: 10, endRadius: 90
                        ))
                        .frame(width: 180, height: 180)
                        // Add a slow pulse to the background glow
                        .phaseAnimator([false, true]) { content, phase in
                            content
                                .scaleEffect(phase ? 1.05 : 0.95)
                                .opacity(phase ? 1.0 : 0.7)
                        } animation: { _ in
                            .easeInOut(duration: 2.0).repeatForever(autoreverses: true)
                        }
                    
                    Text("🐍") // The Basilisk / Chamber theme!
                        .font(.system(size: 80))
                        .shadow(color: .green.opacity(0.5), radius: 10, x: 0, y: 5)
                }

                // Title
                VStack(spacing: 8) {
                    Text("Chamber of Secrets")
                        .font(.system(.title, design: .serif).bold()) // Serif font for that HP book feel
                        .foregroundStyle(
                            LinearGradient(
                                colors:[.teal, .green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Messages in this room vanish into the shadows. Whether read or not.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Magical Feature Cards Grid
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        SecretFeatureCard(
                            icon: "hourglass.circle.fill", // Time running out
                            color: .green,
                            title: "Evanesco", // Vanishing spell
                            subtitle: messageLifetime != nil ? formatLifetime(messageLifetime!) : "Auto-Deletes"
                        )
                        
                        SecretFeatureCard(
                            icon: "lock.shield.fill",
                            color: .purple,
                            title: "Protego", // Shield spell
                            subtitle: "Screenshots Blocked"
                        )
                    }
                    
                    SecretFeatureCard(
                        icon: "eye.slash.fill",
                        color: .teal,
                        title: "Unforgivable Secrecy",
                        subtitle: "End-to-End privacy. Screen recording and broadcasting are fully neutralized.",
                        isFullWidth: true
                    )
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
                Text("🐍")
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

#if os(iOS)
/// Re-enables the interactive pop gesture that SwiftUI disables when the nav bar is hidden.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        SwipeBackViewController()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private class SwipeBackViewController: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}
#endif

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

struct SecretFeatureCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var isFullWidth: Bool = false

    var body: some View {
        VStack(alignment: isFullWidth ? .leading : .center, spacing: 12) {
            // Icon with a glowing backdrop
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .blur(radius: 6)
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.5), radius: 3)
            }
            .frame(maxWidth: isFullWidth ? .none : .infinity, alignment: isFullWidth ? .leading : .center)

            VStack(alignment: isFullWidth ? .leading : .center, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .serif).weight(.bold))
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(isFullWidth ? .leading : .center)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: isFullWidth ? nil : 145)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                // The Animated Glowing Border
                .modifier(MagicalBorderModifier(color: color, cornerRadius: 24))
        }
        // Outer ambient glow
        .shadow(color: color.opacity(0.08), radius: 15, x: 0, y: 8)
    }
}

// MARK: - The Moving Light Animation
struct MagicalBorderModifier: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                // The glowing border line
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            stops:[
                                .init(color: .clear, location: 0.0),
                                .init(color: color.opacity(0.2), location: 0.2),
                                .init(color: color, location: 0.5), // The bright tip of the light
                                .init(color: .white, location: 0.52), // Core of the light
                                .init(color: color, location: 0.54),
                                .init(color: color.opacity(0.2), location: 0.6),
                                .init(color: .clear, location: 1.0)
                            ],
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: 2
                    )
            }
            // A secondary blurred overlay to make the moving line "glow"
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            stops:[
                                .init(color: .clear, location: 0.4),
                                .init(color: color, location: 0.5),
                                .init(color: .clear, location: 0.6)
                            ],
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: 4
                    )
                    .blur(radius: 4)
            }
            // Clip everything to the rounded rectangle so it doesn't bleed outside
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                // Start the continuous rotation
                withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
