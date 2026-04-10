import SwiftUI

struct ContentView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @StateObject private var viewModel = ChatListViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var navigationState = NavigationStateManager.shared

    // MARK: - UI State
    @State private var selectedSection: ChatListViewModel.Section = .chats
    @State private var isShowingNewRoomSheet = false
    @State private var newRoomName = ""
    @State private var isShowingJoinRoomSheet = false
    @State private var availableRooms: [ChatRoom] = []
    @State private var isShowingSearchView = false
    @State private var directStartFriend: ChatUser?
    @State private var previewRequest: FriendRequest?
    @State private var passwordPromptRoom: ChatRoom?

    // MARK: - Alert State
    @State private var showingSignOutAlert = false
    @State private var showingLeaveRoomAlert = false
    @State private var showingDeleteRoomAlert = false
    @State private var roomToLeave: ChatRoom?

    // MARK: - Keyboard Navigation (macOS)
    @State private var selectedRoomIndex: Int? = nil
    @FocusState private var isContentFocused: Bool

    private var headerHeight: CGFloat {
        verticalSizeClass == .compact ? 240 : 320
    }

    #if os(macOS)
    private var columnCount: Int {
        // Match ChatRoomGridView column count
        3 // macOS always uses regular size class
    }

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

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationState.path) {
            ZStack(alignment: .top) {
                // Header background
                LinearGradient(
                    colors: selectedTheme.colors(for: colorScheme).headerBackground,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Header content
                ChatListHeaderView(
                    selectedSection: $selectedSection,
                    sectionSummary: viewModel.sectionSummary(for: selectedSection),
                    pendingRequestCount: viewModel.totalPendingRequestCount,
                    onCreateRoom: { isShowingNewRoomSheet = true },
                    onSearch: { isShowingSearchView = true }
                )

                // Scrollable content
                ChatListContentView(
                    viewModel: viewModel,
                    selectedSection: selectedSection,
                    selectedRoomIndex: selectedRoomIndex,
                    onLeaveRoom: handleLeaveRoom,
                    onStartFriendChat: { friend in directStartFriend = friend },
                    onPreviewRequest: { request in previewRequest = request },
                    onOpenOutgoingRequest: { request in
                        navigationState.path.append(
                            DraftDirectChatSession(
                                user: request.user,
                                roomType: request.roomType,
                                messageLifetime: request.messageLifetime,
                                requestId: request.id
                            )
                        )
                    }
                )
            }
            .navigationDestination(for: ChatRoom.self) { room in
                ChatRoomView(room: room)
                    .onAppear {
                        viewModel.clearUnread(for: room.id)
                    }
            }
            .navigationDestination(for: DraftDirectChatSession.self) { draft in
                FriendRequestDraftView(session: draft)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenChatRoom"))) { notification in
                if let room = notification.userInfo?["room"] as? ChatRoom {
                    if !viewModel.myRooms.contains(where: { $0.id == room.id }) {
                        viewModel.addRoomOptimistically(room)
                    }
                    navigationState.path.append(room)
                } else if let roomId = notification.userInfo?["roomId"] as? String {
                    if let room = viewModel.myRooms.first(where: { $0.id == roomId }) {
                        if navigationState.currentRoomId != roomId {
                            navigationState.path.append(room)
                        }
                    } else {
                        navigationState.pendingRoomId = roomId
                    }
                }
            }
            .onChange(of: viewModel.myRooms) { _, rooms in
                guard let pendingId = navigationState.pendingRoomId,
                      let room = rooms.first(where: { $0.id == pendingId }) else { return }
                navigationState.pendingRoomId = nil
                navigationState.path.append(room)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenDraftChat"))) { notification in
                if let draft = notification.userInfo?["draft"] as? DraftDirectChatSession {
                    navigationState.path.append(draft)
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
                    createRoom: { type, messageLifetime, password in
                        if let room = await viewModel.createRoom(name: newRoomName, type: type, messageLifetime: messageLifetime, password: password) {
                            isShowingNewRoomSheet = false
                            newRoomName = ""
                            try? await Task.sleep(for: .milliseconds(300))
                            navigationState.path.append(room)
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingJoinRoomSheet) {
                JoinRoomSheet(
                    isShowingSheet: $isShowingJoinRoomSheet,
                    availableRooms: availableRooms,
                    joinRoom: { room in
                        Task {
                            let result = await viewModel.joinRoom(room)
                            handleJoinResult(result)
                        }
                    }
                )
            }
            .sheet(item: $passwordPromptRoom) { room in
                RoomPasswordSheet(
                    roomName: room.name,
                    submit: { password in
                        let result = await viewModel.joinRoom(room, password: password)
                        switch result {
                        case .wrongPassword:
                            return "Wrong room password."
                        case .failed(let msg):
                            return msg
                        case .success:
                            passwordPromptRoom = nil
                            return nil
                        case .passwordRequired:
                            return "Password required."
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingSearchView, onDismiss: {
                Task {
                    await viewModel.loadRooms()
                }
            }) {
                SearchView()
            }
            .sheet(item: $previewRequest) { request in
                FriendRequestPreviewView(
                    request: request,
                    approve: {
                        await viewModel.approve(request)
                    },
                    reject: {
                        await viewModel.reject(request)
                    }
                )
            }
            .sheet(item: $directStartFriend) { friend in
                DirectRoomConfigurationSheet(
                    user: friend,
                    actionTitle: "Open Chat"
                ) { roomType, messageLifetime in
                    if let room = await viewModel.startFriendConversation(with: friend, roomType: roomType, messageLifetime: messageLifetime) {
                        navigationState.path.append(room)
                    }
                }
            }
        }
        .task {
            await viewModel.loadRooms()
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                viewModel.signOut()
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
                        await viewModel.leaveRoom(room)
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
                        await viewModel.deleteRoomCompletely(room)
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

    // MARK: - Actions

    private func handleLeaveRoom(_ room: ChatRoom) {
        let action = viewModel.initiateLeaveRoom(room)
        switch action {
        case .confirmLeave(let room):
            roomToLeave = room
            showingLeaveRoomAlert = true
        case .confirmDelete(let room):
            roomToLeave = room
            showingDeleteRoomAlert = true
        }
    }

    private func handleJoinResult(_ result: ChatListViewModel.JoinRoomResult) {
        switch result {
        case .success(let room):
            isShowingJoinRoomSheet = false
            navigationState.path.append(room)
        case .passwordRequired(let room):
            passwordPromptRoom = room
        case .wrongPassword:
            AlertManager.shared.showAlert(title: "Error", message: "Wrong room password.")
        case .failed(let message):
            AlertManager.shared.showAlert(title: "Error", message: message)
        }
    }
}

#Preview {
    ContentView()
}
