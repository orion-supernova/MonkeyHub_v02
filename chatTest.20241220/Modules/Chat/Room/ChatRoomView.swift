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

    private var stableBottomSafeAreaInset: CGFloat {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
        #else
        0
        #endif
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
                    PrivateSpaceWelcomeView(messageLifetime: liveRoom.messageLifetime)
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
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        // ContentView applies these at the destination boundary too; keeping them here protects
        // any future entry point that presents ChatRoomView directly.
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
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
            // Mark this room active for notification suppression here (not synchronously in
            // onAppear) so the @Published write lands just after the push begins, off the
            // transition's synchronous commit.
            navigationState.currentScreen = .chatRoom
            navigationState.currentRoomId = room.id

            // Run the membership check concurrently with the message load so messages (often
            // served instantly from the repository cache) aren't gated behind a network call.
            async let membership: Void = checkMembership()
            await viewModel.loadMessages()
            await membership
            await viewModel.markRead()
            isLoading = false
        }
        .onChange(of: viewModel.messages.count) { _, _ in
            Task { await viewModel.markRead() }
        }
        .onAppear {
            // currentScreen/currentRoomId are set in `.task` (off the push's synchronous commit).
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
        GlassEffectContainer {
            VStack(spacing: 8) {
                if isUserMember {
                    if viewModel.isFetchingNewMessages {
                        SyncingIndicatorView()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if let replyTarget = viewModel.replyingTo {
                        ComposerReplyCard(message: replyTarget) {
                            withAnimation(.spring(response: 0.3)) { viewModel.replyingTo = nil }
                        }
                        .padding(.horizontal, 16)
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
            .padding(.bottom, stableBottomSafeAreaInset)
            .background(
                GeometryReader { chromeProxy in
                    Color.clear
                        .preference(key: BottomChromeHeightPreferenceKey.self, value: chromeProxy.size.height)
                }
            )
        }
        
    }

    private var topControls: some View {
        GlassEffectContainer {
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

struct RoomTitleView: View {
    let title: String
    var roomType: RoomType = .regular
    let avatarImage: PlatformImage?

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    var showFocusRing: Bool = false
    @State private var isExpanded = false
    @State private var collapseTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            if let avatar = avatarImage {
                Image(platformImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.1), lineWidth: 0.5))
            }

            // Subtle Privacy Icon (Replaces Snake/Flame)
            if roomType == .secret {
                Image(systemName: "key.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                // Collapsed: single line. Tapped: all lines needed for the full name.
                .lineLimit(isExpanded ? nil : 1)
                .multilineTextAlignment(.center)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        // Native Liquid Glass — `.interactive()` gives the fluid stretch-on-drag (plain `.regular`
        // is static and reads as a flat material). A rounded rect (not a capsule) so it stays clean
        // when expanded to multiple lines; at the 44pt collapsed height it still reads as a pill.
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        // Clip to the same shape — interactive glass can otherwise mis-render/flicker its shape.
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(selectedTheme.colors(for: colorScheme).primary.first ?? .blue, lineWidth: showFocusRing ? 2 : 0)
        )
        .onTapGesture {
            // Expand to the full multi-line name, then auto-collapse 2s later. Re-tapping
            // restarts the timer (or collapses immediately if already expanded).
            collapseTask?.cancel()
            let willExpand = !isExpanded
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded = willExpand }
            if willExpand {
                collapseTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded = false }
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
/// Re-enables the interactive pop gesture that SwiftUI disables when the nav bar is hidden, and
/// fades the native tab bar with the swipe progress. SwiftUI restores the tab bar only at the end
/// of the pop; driving alpha here gives the chat-app feel users expect during the drag itself.
private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        SwipeBackViewController()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private class SwipeBackViewController: UIViewController {
        private weak var observedPopGesture: UIGestureRecognizer?
        private var isObservingPopGesture = false

        deinit {
            observedPopGesture?.removeTarget(self, action: #selector(handleInteractivePop(_:)))
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            gesture.isEnabled = true
            gesture.delegate = nil
            observePopGestureIfNeeded(gesture)
            hideTabBarForSettledChat()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let coordinator = transitionCoordinator else {
                revealTabBar()
                return
            }

            if coordinator.isInteractive {
                coordinator.notifyWhenInteractionChanges { [weak self] context in
                    if context.isCancelled {
                        self?.hideTabBarForSettledChat()
                    } else {
                        self?.revealTabBar()
                    }
                }
            } else {
                coordinator.animate { [weak self] _ in
                    self?.revealTabBar()
                }
            }
        }

        private func observePopGestureIfNeeded(_ gesture: UIGestureRecognizer) {
            guard observedPopGesture !== gesture else { return }
            if isObservingPopGesture {
                observedPopGesture?.removeTarget(self, action: #selector(handleInteractivePop(_:)))
            }
            observedPopGesture = gesture
            isObservingPopGesture = true
            gesture.addTarget(self, action: #selector(handleInteractivePop(_:)))
        }

        @objc private func handleInteractivePop(_ gesture: UIPanGestureRecognizer) {
            guard let tabBar = tabBarController?.tabBar,
                  let baseView = view else { return }
            let hostView = baseView.window ?? baseView

            switch gesture.state {
            case .began, .changed:
                let width = max(hostView.bounds.width, 1)
                let progress = min(max(gesture.translation(in: hostView).x / width, 0), 1)
                tabBar.layer.removeAllAnimations()
                tabBar.isHidden = false
                tabBar.alpha = progress

            case .ended, .cancelled, .failed:
                let width = max(hostView.bounds.width, 1)
                let progress = min(max(gesture.translation(in: hostView).x / width, 0), 1)
                let velocity = gesture.velocity(in: hostView).x
                let shouldReveal = progress > 0.45 || velocity > 600
                animateTabBar(visible: shouldReveal)

            default:
                break
            }
        }

        private func hideTabBarForSettledChat() {
            guard let tabBar = tabBarController?.tabBar else { return }
            tabBar.layer.removeAllAnimations()
            tabBar.alpha = 0
            tabBar.isHidden = true
        }

        private func revealTabBar() {
            animateTabBar(visible: true)
        }

        private func animateTabBar(visible: Bool) {
            guard let tabBar = tabBarController?.tabBar else { return }
            tabBar.isHidden = false
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut]
            ) {
                tabBar.alpha = visible ? 1 : 0
            } completion: { _ in
                tabBar.isHidden = !visible
            }
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

struct PrivateFeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var isFullWidth: Bool = false

    var body: some View {
        Group {
            if isFullWidth {
                // Horizontal Layout: Icon on the Left
                HStack(spacing: 16) {
                    iconView
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption.bold())
                        Spacer()
                            .frame(height: 2)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                // Vertical Layout: Icon on Top
                VStack(spacing: 8) {
                    iconView
                    
                    VStack(spacing: 2) {
                        Text(title)
                            .font(.caption.bold())
                        Spacer()
                            .frame(height: 2)
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: isFullWidth ? 0 : 120) // Give vertical cards a consistent height
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        }
    }

    // Extracted Icon View for consistency
    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 20))
            .foregroundStyle(.primary.opacity(0.7))
            .frame(width: 32, height: 32)
            .background(Circle().fill(.primary.opacity(0.03)))
    }
}

// MARK: - Private Space Welcome View
struct PrivateSpaceWelcomeView: View {
    let messageLifetime: TimeInterval?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Clean, Professional Icon
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "key.shield") // Universal SF Symbol
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Text("Secret Space")
                    .font(.system(.title3, design: .rounded).bold())
                
                Text("Messages in this room are ephemeral. They are automatically removed based on the room's security policy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Simple Feature Grid
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    PrivateFeatureCard(icon: "clock.badge.exclamationmark", title: "Auto-Delete", subtitle: messageLifetime != nil ? "Varies" : "Timed")
                    PrivateFeatureCard(icon: "hand.raised.fill", title: "No Capture", subtitle: "Screenshots Restricted")
                }
                PrivateFeatureCard(icon: "lock.fill", title: "Much More Privacy", subtitle: "Enjoy extra security features on top of already existing privacy focus.", isFullWidth: true)
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
}
