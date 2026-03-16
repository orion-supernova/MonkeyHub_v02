//
//  ContentView.swift
//  chatTest.20241220
//
//  Created by muratcankoc on 20/12/2024.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @StateObject private var viewModel = ChatListViewModel()
    @State private var isShowingNewRoomSheet = false
    @State private var newRoomName = ""
    @State private var showingSignOutAlert = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var isShowingJoinRoomSheet = false
    @State private var availableRooms: [ChatRoom] = []
    @State private var isShowingSearchView = false
    @StateObject private var navigationState = NavigationStateManager.shared

    // MARK: - Keyboard Navigation (macOS)
    @State private var selectedRoomIndex: Int? = nil
    @FocusState private var isContentFocused: Bool

    // MARK: - Leave Room State
    @State private var showingLeaveRoomAlert = false
    @State private var showingDeleteRoomAlert = false
    @State private var roomToLeave: ChatRoom?

    // MARK: - Room Operations
    private func loadData() async {
        await viewModel.loadRooms()
    }

    private func createRoom(type: RoomType, messageLifetime: TimeInterval?) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        do {
            let roomId = try await ConvexChatAPI.shared.createRoom(
                name: newRoomName,
                userId: userId,
                isPrivate: true,
                type: type,
                messageLifetime: messageLifetime
            )
            let room = ChatRoom(
                id: roomId,
                name: newRoomName,
                createdBy: userId,
                participants: [userId],
                type: type,
                messageLifetime: messageLifetime
            )
            viewModel.addRoomOptimistically(room)
            isShowingNewRoomSheet = false
            newRoomName = ""
            try? await Task.sleep(nanoseconds: 300_000_000)
            navigationState.path.append(room)
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private func initiateLeaveRoom(_ room: ChatRoom) {
        roomToLeave = room
        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""
        let isLastUser = room.participants.count == 1 && room.participants.contains(userId)

        if isLastUser {
            showingDeleteRoomAlert = true
        } else {
            showingLeaveRoomAlert = true
        }
    }

    private func leaveRoom(_ room: ChatRoom) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        viewModel.removeRoomOptimistically(room.id)
        do {
            try await ConvexChatAPI.shared.leaveRoom(roomId: room.id, userId: userId)
        } catch {
            viewModel.addRoomOptimistically(room)
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private func deleteRoomCompletely(_ room: ChatRoom) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        viewModel.removeRoomOptimistically(room.id)
        do {
            try await ConvexChatAPI.shared.deleteRoom(roomId: room.id, userId: userId)
        } catch {
            viewModel.addRoomOptimistically(room)
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad or large screen: 3 columns
            return [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ]
        } else {
            // iPhone: 2 columns
            return [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ]
        }
    }

    #if os(macOS)
    private var columnCount: Int { gridColumns.count }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        let roomCount = viewModel.myRooms.count
        guard roomCount > 0 else { return }

        guard let current = selectedRoomIndex else {
            selectedRoomIndex = 0
            return
        }

        var newIndex = current
        switch direction {
        case .left:
            newIndex = max(current - 1, 0)
        case .right:
            newIndex = min(current + 1, roomCount - 1)
        case .up:
            let candidate = current - columnCount
            if candidate >= 0 { newIndex = candidate }
        case .down:
            let candidate = current + columnCount
            if candidate < roomCount { newIndex = candidate }
        @unknown default:
            break
        }
        selectedRoomIndex = newIndex
    }
    #endif

    private var headerHeight: CGFloat {
        switch verticalSizeClass {
        case .compact:
            return 200  // Landscape mode
        default:
            return 260  // Portrait mode
        }
    }

    var body: some View {
        NavigationStack(path: $navigationState.path) {
            ZStack(alignment: .top) {
                // Header background that covers status bar and header content
                LinearGradient(
                    colors: selectedTheme.colors(for: colorScheme).headerBackground,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .frame(height: headerHeight)

                ScrollView {
                    VStack(spacing: 0) {
                        // Header content
                        VStack(spacing: verticalSizeClass == .compact ? 12 : 20) {
                            // Status bar spacing
                            Color.clear
                                .frame(height: verticalSizeClass == .compact ? 20 : 50)

                            // Title and action buttons
                            VStack(spacing: 16) {
                                // Title and room count
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Chat Rooms")
                                            .font(
                                                .system(
                                                    size: verticalSizeClass == .compact ? 28 : 34,
                                                    weight: .bold
                                                )
                                            )
                                            .foregroundStyle(
                                                selectedTheme.colors(for: colorScheme).text)

                                        Text(
                                            "\(viewModel.myRooms.count) Active Room\(viewModel.myRooms.count == 1 ? "" : "s")"
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).text.opacity(0.8)
                                        )
                                    }

                                    Spacer()
                                }

                                // Action buttons
                                HStack(spacing: 12) {
                                    // Create Room button
                                    Button {
                                        isShowingNewRoomSheet = true
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "plus.circle.fill")
                                            Text("New Room")
                                        }
                                        .font(.headline)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).text
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            LinearGradient(
                                                colors: [
                                                    selectedTheme.colors(for: colorScheme)
                                                        .headerOverlay,
                                                    selectedTheme.colors(for: colorScheme)
                                                        .headerOverlay.opacity(0.8),
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    selectedTheme.colors(for: colorScheme).text
                                                        .opacity(0.2),
                                                    lineWidth: 1
                                                )
                                        )
#if os(macOS)
                                        .buttonStyle(.plain)
                                        .contentShape(RoundedRectangle(cornerRadius: 16))
#endif
                                    }

                                    // Search button
                                    Button {
                                        isShowingSearchView = true
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "magnifyingglass")
                                            Text("Search")
                                        }
                                        .font(.headline)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).text
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            LinearGradient(
                                                colors: [
                                                    selectedTheme.colors(for: colorScheme)
                                                        .headerOverlay,
                                                    selectedTheme.colors(for: colorScheme)
                                                        .headerOverlay.opacity(0.8),
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    selectedTheme.colors(for: colorScheme).text
                                                        .opacity(0.2),
                                                    lineWidth: 1
                                                )
                                        )
#if os(macOS)
                                        .buttonStyle(.plain)
                                        .contentShape(RoundedRectangle(cornerRadius: 16))
#endif
                                    }
                                }
                                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 24)
#if os(macOS)
                                .buttonStyle(.plain)
#endif
                            }
                            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 24)
                            .padding(.bottom, verticalSizeClass == .compact ? 16 : 24)

                            // Rooms list
                            LazyVStack(spacing: 16) {
                                if viewModel.myRooms.isEmpty {
                                    if viewModel.isLoading {
                                        VStack(spacing: 16) {
                                            ProgressView()
                                                .scaleEffect(1.5)
                                            Text("Loading Rooms...")
                                                .font(.subheadline)
                                                .foregroundStyle(.gray)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(40)
                                    } else {
                                        VStack(spacing: 16) {
                                            Image(systemName: "bubble.left.circle.fill")
                                                .font(.system(size: 60))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: selectedTheme.colors(for: colorScheme)
                                                            .primary,
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .padding(.bottom, 8)

                                            Text("No Active Rooms")
                                                .font(.title2.bold())
                                                .foregroundStyle(
                                                    selectedTheme.colors(for: colorScheme).textPrimary)

                                            Text("Create a new room to start chatting")
                                                .font(.subheadline)
                                                .foregroundStyle(
                                                    selectedTheme.colors(for: colorScheme).textSecondary
                                                )
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(40)
                                    }
                                } else {
                                    VStack(spacing: 24) {
                                        // Section header
                                        HStack {
                                            Text("Your Rooms")
                                                .font(.title2.bold())
                                                .foregroundStyle(
                                                    selectedTheme.colors(for: colorScheme)
                                                        .textPrimary)

                                            Spacer()

                                            Text("\(viewModel.myRooms.count) Total")
                                                .font(.subheadline)
                                                .foregroundStyle(
                                                    selectedTheme.colors(for: colorScheme)
                                                        .textSecondary
                                                )
                                        }
                                        .padding(
                                            .horizontal, horizontalSizeClass == .regular ? 32 : 20)

                                        // Rooms grid
                                        LazyVGrid(columns: gridColumns, spacing: 16) {
                                            ForEach(Array(viewModel.myRooms.enumerated()), id: \.element.id) { index, room in
                                                NavigationLink(value: room) {
                                                    EnhancedRoomCard(room: room, unreadCount: viewModel.unreadCounts[room.id] ?? 0, isSelected: selectedRoomIndex == index) {
                                                        initiateLeaveRoom(room)
                                                    }
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(
                                            .horizontal, horizontalSizeClass == .regular ? 32 : 16)
                                    }
                                }
                            }
                            .padding(.top, 16)
                            .background(
                                ZStack {
                                    // Main background with shadow
                                    RoundedRectangle(cornerRadius: 32)
                                        .fill(selectedTheme.colors(for: colorScheme).background)
                                        .shadow(
                                            color: selectedTheme.colors(for: colorScheme).primary[0]
                                                .opacity(0.1),
                                            radius: 20,
                                            y: -10
                                        )

                                    // Extended top edge overlay
                                    Rectangle()
                                        .fill(selectedTheme.colors(for: colorScheme).background)
                                        .frame(height: 50)  // Increased height
                                        .offset(y: -25)  // Adjusted offset
                                }
                            )
                            .offset(y: -40)  // Increased overlap with header
                            .padding(.top, 40)  // Adjusted padding to compensate
                        }
                    }
                }
            }
            .navigationDestination(for: ChatRoom.self) { room in
                ChatRoomView(room: room)
                    .onAppear {
                        viewModel.clearUnread(for: room.id)
                    }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenChatRoom"))) { notification in
                // Handle room object passed directly (for newly joined rooms from search)
                if let room = notification.userInfo?["room"] as? ChatRoom {
                    // Add to local list if not present, then navigate
                    if !viewModel.myRooms.contains(where: { $0.id == room.id }) {
                        viewModel.addRoomOptimistically(room)
                    }
                    navigationState.path.append(room)
                }
                // Handle room ID (for existing rooms already in myRooms)
                else if let roomId = notification.userInfo?["roomId"] as? String {
                    if let room = viewModel.myRooms.first(where: { $0.id == roomId }) {
                        navigationState.path.append(room)
                    }
                }
            }
            .background(selectedTheme.colors(for: colorScheme).background)
            #if os(macOS)
            .focused($isContentFocused)
            .focusEffectDisabled()
            .onAppear { isContentFocused = true }
            .onMoveCommand { direction in
                handleMoveCommand(direction)
            }
            .onExitCommand {
                selectedRoomIndex = nil
            }
            .onKeyPress(.return) {
                if let index = selectedRoomIndex, index < viewModel.myRooms.count {
                    navigationState.path.append(viewModel.myRooms[index])
                    selectedRoomIndex = nil
                    return .handled
                }
                return .ignored
            }
            .onChange(of: viewModel.myRooms.count) { _, newCount in
                if let index = selectedRoomIndex, index >= newCount {
                    selectedRoomIndex = newCount > 0 ? newCount - 1 : nil
                }
            }
            #endif
            .sheet(isPresented: $isShowingNewRoomSheet) {
                EnhancedNewRoomSheet(
                    isShowingSheet: $isShowingNewRoomSheet,
                    roomName: $newRoomName,
                    createRoom: createRoom
                )
            }
            .sheet(isPresented: $isShowingJoinRoomSheet) {
                JoinRoomSheet(
                    isShowingSheet: $isShowingJoinRoomSheet,
                    availableRooms: availableRooms,
                    joinRoom: { room in
                        Task {
                            await joinRoom(room)
                        }
                    }
                )
            }
//            .sheet(isPresented: $isShowingFindFriendSheet) {
//                FindFriendSheet(
//                    isShowingSheet: $isShowingFindFriendSheet,
//                    createPrivateRoom: { friend in
//                        Task {
//                            await createPrivateRoom(with: friend)
//                        }
//                    }
//                )
//            }
            .sheet(isPresented: $isShowingSearchView, onDismiss: {
                // Refresh room list after search sheet is dismissed (in case user joined a room)
                Task {
                    await loadData()
                }
            }) {
                SearchView()
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                // Refresh room list when app comes to foreground
                // This handles: removed from rooms, added to new rooms
                Task {
                    await loadData()
                }
            }
        }
        // Listen for real-time room deletion notifications
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RoomWasDeleted"))) { notification in
            if let roomId = notification.userInfo?["roomId"] as? String {
                print("📥 ContentView: Room \(roomId) was deleted, updating UI")
                viewModel.removeRoomOptimistically(roomId)
            }
        }
        // Listen for real-time removal from room notifications
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserRemovedFromRoom"))) { notification in
            if let roomId = notification.userInfo?["roomId"] as? String {
                print("📥 ContentView: User removed from room \(roomId), updating UI")
                viewModel.removeRoomOptimistically(roomId)
            }
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    await signOut()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Leave Room", isPresented: $showingLeaveRoomAlert) {
            Button("Cancel", role: .cancel) {
                roomToLeave = nil
            }
            Button("Leave", role: .destructive) {
                if let room = roomToLeave {
                    Task {
                        await leaveRoom(room)
                        roomToLeave = nil
                    }
                }
            }
        } message: {
            Text("Are you sure you want to leave this room?")
        }
        .alert("Delete Room", isPresented: $showingDeleteRoomAlert) {
            Button("Cancel", role: .cancel) {
                roomToLeave = nil
            }
            Button("Delete", role: .destructive) {
                if let room = roomToLeave {
                    Task {
                        await deleteRoomCompletely(room)
                        roomToLeave = nil
                    }
                }
            }
        } message: {
            if let room = roomToLeave {
                Text("You are the only member of \"\(room.name)\". Leaving will permanently delete this room and all its messages. This action cannot be undone.")
            } else {
                Text("This room will be permanently deleted.")
            }
        }
    }

    private func signOut() async {
        ConvexAuthService.shared.signOut()
    }

    private func themeIcon(for theme: AppTheme) -> String {
        switch theme {
        case .basic:
            return "circle.grid.cross.fill"
        case .cyberpunk:
            return "bolt.circle.fill"
        case .retroWave:
            return "sunset.fill"
        case .neonNight:
            return "sparkles"
        case .deepOcean:
            return "water.waves"
        }
    }

    private func joinRoom(_ room: ChatRoom) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        do {
            try await ConvexChatAPI.shared.joinRoom(roomId: room.id, userId: userId)
            await loadData()
            isShowingJoinRoomSheet = false
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private func loadAvailableRooms() async {
        do {
            availableRooms = try await ConvexChatAPI.shared.fetchPublicRooms()
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private func createPrivateRoom(with friend: ChatUser) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        do {
            let roomId = try await ConvexChatAPI.shared.getOrCreateDM(userId: userId, friendId: friend.id)
            let room = ChatRoom(
                id: roomId,
                name: "Chat with \(friend.displayName)",
                createdBy: userId,
                participants: [userId, friend.id]
            )
            viewModel.addRoomOptimistically(room)
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }
}

struct EnhancedRoomCard: View {
    let room: ChatRoom
    let unreadCount: Int
    var isSelected: Bool = false
    let action: () -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @State private var roomAvatarImage: PlatformImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with room avatar and leave button
            HStack {
                // Room avatar
                Group {
                    if let avatarImage = roomAvatarImage {
                        Image(platformImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: selectedTheme.colors(for: colorScheme).primary,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            Text(room.name.prefix(1).uppercased())
                                .font(.headline.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                        }
                        .frame(width: 40, height: 40)
                    }
                }
                .shadow(
                    color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.2),
                    radius: 4, y: 2)
                .onAppear {
                    loadRoomAvatar()
                }

                Spacer()

                // Header right side (Badges + Action)
                HStack(spacing: 8) {
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }

                    // Leave button
                    Button(action: action) {
                        Image(systemName: "door.left.hand.open")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).destructive)
                            .frame(width: 28, height: 28)
                            .background(selectedTheme.colors(for: colorScheme).destructive.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .contentShape(Circle())
#if os(macOS)
                    .buttonStyle(.borderless)
#endif
                }
            }

            // Room info
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    .lineLimit(1)

                Group {
                    if let lastMessage = room.lastMessage {
                        Text(lastMessage)
                    } else {
                        Text("No messages yet")
                            .italic()
                            .opacity(0.6)
                    }
                }
                .font(.caption)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                .lineLimit(1)
            }
            
            // Footer (Participants) - No Spacer above it
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .imageScale(.small)
                Text("\(room.participants.count)")
                
                Spacer()
                
                if room.type == .secret {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                }
            }
            .font(.caption2)
            .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(selectedTheme.colors(for: colorScheme).cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(
            color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.1), radius: 8, y: 4
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isSelected
                        ? selectedTheme.colors(for: colorScheme).accent
                        : selectedTheme.colors(for: colorScheme).accent.opacity(0.1),
                    lineWidth: isSelected ? 2.5 : 1)
        )
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
    
    private func loadRoomAvatar() {
        // Try persisted avatarURL first (resolving filename to current session's path)
        if let avatarURL = room.avatarURL {
            let filename = avatarURL.lastPathComponent
            if let resolvedURL = AssetPersistenceService.shared.getURL(for: filename),
               let data = try? Data(contentsOf: resolvedURL),
               let image = PlatformImage.fromData(data) {
                roomAvatarImage = image
                return
            }
        }

        // Fallback: fetch from Convex storage if storageId available
        if let storageId = room.avatarStorageId {
            Task { await fetchAvatarFromConvex(storageId: storageId) }
        }
    }

    private func fetchAvatarFromConvex(storageId: String) async {
        do {
            if let urlString = try await ConvexChatAPI.shared.getFileURL(storageId: storageId),
               let url = URL(string: urlString) {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = PlatformImage.fromData(data) {
                    await MainActor.run { roomAvatarImage = image }
                }
            }
        } catch {
            // Silently fail — show placeholder
        }
    }
}

struct EnhancedNewRoomSheet: View {
    @Binding var isShowingSheet: Bool
    @Binding var roomName: String
    @State private var selectedType: RoomType = .regular
    @State private var messageLifetime: TimeInterval = 300  // 5 minutes default
    let createRoom: (RoomType, TimeInterval?) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @State private var animateContent = false
    @State private var selectedOptionId: TimeInterval?
    @Namespace private var animation
    @FocusState private var isRoomNameFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollID = UUID()  // For scroll anchor
    @Environment(\.colorScheme) private var colorScheme

    private let lifetimeOptions: [(String, TimeInterval)] = [
        ("5 minutes", 300),
        ("1 hour", 3600),
        ("24 hours", 86400),
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Enhanced Header with animation
                        VStack(spacing: 8) {
                            Text("Create New Room")
                                .font(.title.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                                .opacity(animateContent ? 1 : 0)
                                .offset(y: animateContent ? 0 : 20)

                            Text("Select room type and customize settings")
                                .font(.subheadline)
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).textSecondary
                                )
                                .opacity(animateContent ? 1 : 0)
                                .offset(y: animateContent ? 0 : 20)
                        }
                        .padding(.top, 12)

                        // Room Type Selector with improved animations
                        VStack(alignment: .leading, spacing: 20) {
                            Text("ROOM TYPE")
                                .font(.caption.bold())
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).textSecondary
                                )
                                .padding(.leading, 4)
                                .opacity(animateContent ? 1 : 0)
                                .offset(y: animateContent ? 0 : 20)

                            VStack(spacing: 16) {
                                ForEach([RoomType.regular, .secret], id: \.self) { type in
                                    RoomTypeButton(
                                        type: type,
                                        selectedType: $selectedType,
                                        selectedTheme: selectedTheme,
                                        animateContent: animateContent
                                    )
                                }
                            }
                        }

                        // Message Lifetime Selector with improved animations
                        if selectedType == .secret {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("MESSAGE LIFETIME")
                                    .font(.caption.bold())
                                    .foregroundStyle(
                                        selectedTheme.colors(for: colorScheme).textSecondary
                                    )
                                    .padding(.leading, 4)
                                    .transition(.move(edge: .top).combined(with: .opacity))

                                VStack(spacing: 12) {
                                    ForEach(lifetimeOptions, id: \.1) { option in
                                        Button {
                                            withAnimation(.spring(duration: 0.3)) {
                                                messageLifetime = option.1
                                                selectedOptionId = option.1
                                            }
                                        } label: {
                                            HStack {
                                                Text(option.0)
                                                    .font(.subheadline)
                                                    .foregroundStyle(
                                                        selectedTheme.colors(for: colorScheme)
                                                            .textPrimary)

                                                Spacer()

                                                if messageLifetime == option.1 {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(
                                                            selectedTheme.colors(for: colorScheme)
                                                                .accent
                                                        )
                                                        .matchedGeometryEffect(
                                                            id: "check\(option.1)",
                                                            in: animation
                                                        )
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(
                                                        selectedTheme.colors(for: colorScheme)
                                                            .cardBackground
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .strokeBorder(
                                                                messageLifetime == option.1
                                                                    ? selectedTheme.colors(
                                                                        for: colorScheme
                                                                    ).accent
                                                                    : selectedTheme.colors(
                                                                        for: colorScheme
                                                                    ).textSecondary
                                                                        .opacity(0.1),
                                                                lineWidth: messageLifetime
                                                                    == option.1
                                                                    ? 1.5 : 1
                                                            )
                                                    )
                                            )
                                            .scaleEffect(messageLifetime == option.1 ? 1.02 : 1)
                                        }
                                        .buttonStyle(.plain)
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                }
                            }
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Room name input with simplified keyboard handling
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ROOM NAME")
                                .font(.caption.bold())
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).textSecondary
                                )
                                .padding(.leading, 4)
                                .opacity(animateContent ? 1 : 0)
                                .offset(y: animateContent ? 0 : 20)

                            TextField("Enter room name", text: $roomName)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(selectedTheme.colors(for: colorScheme).cardBackground)
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            roomName.isEmpty
                                                ? selectedTheme.colors(for: colorScheme)
                                                    .textSecondary
                                                    .opacity(0.1)
                                                : selectedTheme.colors(for: colorScheme).accent
                                                    .opacity(
                                                        0.2),
                                            lineWidth: 1
                                        )
                                )
                                .focused($isRoomNameFocused)
                        }
                        .id(scrollID)  // Add scroll anchor
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)

                        // Create button with enhanced animation
                        Button {
                            // Add haptic feedback
                        #if canImport(UIKit)
                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                            impactMed.impactOccurred()
                        #endif

                            Task {
                                await createRoom(
                                    selectedType,
                                    selectedType == .secret ? messageLifetime : nil
                                )
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if selectedType == .secret {
                                    Image(systemName: "wand.and.rays")
                                        .symbolEffect(.variableColor.cumulative.hideInactiveLayers.nonReversing, options: .repeat(.continuous))
                                        .transition(.scale.combined(with: .opacity))
                                    Text("Coming Soon!")
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .transition(.scale.combined(with: .opacity))
                                    Text("Create Room")
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: selectedType == .secret
                                        ? [Color.gray, Color.gray.opacity(0.7)]
                                        : selectedTheme.colors(for: colorScheme).primary,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(
                                color: selectedType == .secret
                                    ? Color.clear
                                    : selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3),
                                radius: 5, y: 2
                            )
                            .scaleEffect(roomName.isEmpty || selectedType == .secret ? 0.98 : 1)
                        }
                        .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedType == .secret)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)
#if os(macOS)
                        .buttonStyle(.plain)
                        .focusable(false)
#endif
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(20)
                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 20 : 16)
                }
                .onChange(of: isRoomNameFocused) { _, isFocused in
                    if isFocused {
                        withAnimation {
                            proxy.scrollTo(scrollID, anchor: .bottom)
                        }
                    }
                }
                .background(selectedTheme.colors(for: colorScheme).background)
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isRoomNameFocused = false
                            }
                        }
                        .foregroundStyle(
                            colorScheme == .dark
                                ? selectedTheme.colors(for: colorScheme).accent
                                : selectedTheme.colors(for: colorScheme).primary[0]
                        )
                    }

                    // Add close button
                    ToolbarItem(placement: {
                        #if canImport(UIKit)
                        return .navigationBarTrailing
                        #else
                        return .automatic
                        #endif
                    }()) {
                        Button {
                            isShowingSheet = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).textSecondary)
                        }
#if os(macOS)
                        .buttonStyle(.plain)
                        .focusable(false)
#endif
                        .contentShape(Circle())
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    animateContent = true
                }
            }
            .onChange(of: selectedType) { _, _ in
                #if canImport(UIKit)
                let impactLight = UIImpactFeedbackGenerator(style: .light)
                impactLight.impactOccurred()
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 560, minHeight: 500, idealHeight: 620)
        #else
        .presentationDetents([
            .height(selectedType == .secret ? 760 : 620),
            .large,
        ])
        .presentationDragIndicator(.visible)
        .presentationBackground(selectedTheme.colors(for: colorScheme).background)
        .interactiveDismissDisabled()
        #endif
    }
}

struct JoinRoomSheet: View {
    @Binding var isShowingSheet: Bool
    let availableRooms: [ChatRoom]
    let joinRoom: (ChatRoom) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Join Room")
                    .font(.title.bold())
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                Text("Join an existing room")
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }

            if availableRooms.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("No Rooms Available")
                        .font(.title2.bold())
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                    Text("Create a new room or try again later")
                        .font(.subheadline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(availableRooms) { room in
                            Button {
                                Task {
                                    await joinRoom(room)
                                }
                            } label: {
                                HStack(spacing: 16) {
                                    // Room icon
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: selectedTheme.colors(for: colorScheme)
                                                        .primary,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )

                                        Image(
                                            systemName: room.type == .regular
                                                ? "bubble.left" : "lock.shield"
                                        )
                                        .font(.title3.bold())
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).text)
                                    }
                                    .frame(width: 44, height: 44)

                                    // Room info
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(room.name)
                                            .font(.headline)
                                            .foregroundStyle(
                                                selectedTheme.colors(for: colorScheme).textPrimary)

                                        HStack {
                                            Image(systemName: "person.2.fill")
                                                .imageScale(.small)
                                            Text("\(room.participants.count) members")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.headline)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).textSecondary)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(
                                            selectedTheme.colors(for: colorScheme).accent.opacity(
                                                0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, 24)
        .background(selectedTheme.colors(for: colorScheme).background)
    }
}

#Preview {
    ContentView()
}

struct RoomTypeButton: View {
    let type: RoomType
    @Binding var selectedType: RoomType
    let selectedTheme: AppTheme
    let animateContent: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                selectedType = type
            }
        } label: {
            HStack(spacing: 16) {
                // Room type icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: selectedType == type
                                    ? selectedTheme.colors(for: colorScheme).primary
                                    : [selectedTheme.colors(for: colorScheme).cardBackground],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(
                            color: selectedType == type
                                ? selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3)
                                : .clear,
                            radius: 5, y: 2
                        )

                    Image(
                        systemName: type == .regular
                            ? "bubble.left.circle.fill"
                            : "lock.shield.fill"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        selectedType == type
                            ? selectedTheme.colors(for: colorScheme).text
                            : selectedTheme.colors(for: colorScheme).textSecondary
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        type == .regular
                            ? "Regular Room" : "Chamber of Secrets"
                    )
                    .font(.headline)
                    .foregroundStyle(
                        selectedTheme.colors(for: colorScheme).textPrimary
                    )

                    Text(
                        type == .regular
                            ? "Standard chat room with permanent messages"
                            : "Secret room with self-destructing messages"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        selectedTheme.colors(for: colorScheme).textSecondary
                    )
                    .lineLimit(2)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(
                        selectedTheme.colors(for: colorScheme).accent
                    )
                    .opacity(selectedType == type ? 1 : 0)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedTheme.colors(for: colorScheme).cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        selectedType == type
                            ? selectedTheme.colors(for: colorScheme).accent
                            : selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.1),
                        lineWidth: selectedType == type ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(animateContent ? 1 : 0)
        .offset(y: animateContent ? 0 : 20)
    }
}
