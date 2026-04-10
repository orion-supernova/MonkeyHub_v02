import SwiftUI
import Combine

@MainActor
class ChatListViewModel: ObservableObject {
    enum Section: String, CaseIterable {
        case chats = "Chats"
        case friends = "Friends"
        case requests = "Requests"

        var icon: String {
            switch self {
            case .chats:
                return "bubble.left.and.bubble.right.fill"
            case .friends:
                return "person.2.fill"
            case .requests:
                return "person.badge.plus"
            }
        }
    }

    enum JoinRoomResult {
        case success(ChatRoom)
        case passwordRequired(ChatRoom)
        case wrongPassword
        case failed(String)
    }

    enum LeaveAction {
        case confirmLeave(ChatRoom)
        case confirmDelete(ChatRoom)
    }

    @Published var myRooms: [ChatRoom] = []
    @Published var unreadCounts: [String: Int] = [:]
    @Published var roomListTyping: [String: [String]] = [:]
    @Published var isLoading = false
    @Published var friends: [ChatUser] = []
    @Published var incomingRequests: [FriendRequest] = []
    @Published var outgoingRequests: [FriendRequest] = []

    private let repository = ChatRepository.shared
    private let convexAPI = ConvexChatAPI.shared
    private var cancellables = Set<AnyCancellable>()

    private var userId: String {
        userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
    }

    init() {
        setupBindings()
    }

    private func setupBindings() {
        repository.$rooms
            .receive(on: DispatchQueue.main)
            .assign(to: \.myRooms, on: self)
            .store(in: &cancellables)

        repository.$unreadCounts
            .receive(on: DispatchQueue.main)
            .assign(to: \.unreadCounts, on: self)
            .store(in: &cancellables)

        repository.$roomListTyping
            .receive(on: DispatchQueue.main)
            .assign(to: \.roomListTyping, on: self)
            .store(in: &cancellables)

        repository.$friends
            .receive(on: DispatchQueue.main)
            .assign(to: \.friends, on: self)
            .store(in: &cancellables)

        repository.$incomingRequests
            .receive(on: DispatchQueue.main)
            .assign(to: \.incomingRequests, on: self)
            .store(in: &cancellables)

        repository.$outgoingRequests
            .receive(on: DispatchQueue.main)
            .assign(to: \.outgoingRequests, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func loadRooms() async {
        isLoading = true
        await repository.ensureRoomsLoaded()
        isLoading = false
    }

    func refreshRooms() async {
        isLoading = true
        await repository.fetchRooms(force: true)
        isLoading = false
    }

    // MARK: - Room Operations

    func createRoom(name: String, type: RoomType, messageLifetime: TimeInterval?, password: String?) async -> ChatRoom? {
        let passwordHash = password.map { SecurityUtils.sha256($0) }
        do {
            let roomId = try await convexAPI.createRoom(
                name: name,
                userId: userId,
                isPrivate: true,
                type: type,
                messageLifetime: messageLifetime,
                passwordHash: passwordHash
            )
            let room = ChatRoom(
                id: roomId,
                name: name,
                createdBy: userId,
                participants: [userId],
                memberCount: 1,
                type: type,
                messageLifetime: messageLifetime,
                hasPassword: passwordHash != nil
            )
            repository.addRoomOptimistically(room)
            return room
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
            return nil
        }
    }

    func joinRoom(_ room: ChatRoom, password: String? = nil) async -> JoinRoomResult {
        let passwordHash = password.map { SecurityUtils.sha256($0) }
        do {
            try await convexAPI.joinRoom(roomId: room.id, userId: userId, passwordHash: passwordHash)
            await repository.fetchRooms(force: true)
            if let joinedRoom = myRooms.first(where: { $0.id == room.id }) {
                return .success(joinedRoom)
            }
            return .success(room)
        } catch {
            let message = friendlyErrorMessage(error)
            if message.contains("ROOM_PASSWORD_REQUIRED") {
                return .passwordRequired(room)
            } else if message.contains("ROOM_PASSWORD_INVALID") {
                return .wrongPassword
            } else {
                return .failed(message)
            }
        }
    }

    func initiateLeaveRoom(_ room: ChatRoom) -> LeaveAction {
        let isLastUser = room.participants.count == 1 && room.participants.contains(userId)
        if isLastUser {
            return .confirmDelete(room)
        } else {
            return .confirmLeave(room)
        }
    }

    func leaveRoom(_ room: ChatRoom) async {
        repository.removeRoomOptimistically(room.id)
        do {
            try await convexAPI.leaveRoom(roomId: room.id, userId: userId)
        } catch {
            repository.addRoomOptimistically(room)
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    func deleteRoomCompletely(_ room: ChatRoom) async {
        repository.removeRoomOptimistically(room.id)
        do {
            try await convexAPI.deleteRoom(roomId: room.id, userId: userId)
        } catch {
            repository.addRoomOptimistically(room)
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    // MARK: - Friend / DM Operations

    func startFriendConversation(with friend: ChatUser, roomType: RoomType, messageLifetime: TimeInterval?) async -> ChatRoom? {
        do {
            let roomId = try await convexAPI.getOrCreateDM(
                userId: userId,
                friendId: friend.id,
                roomType: roomType,
                messageLifetime: messageLifetime
            )
            let room = ChatRoom(
                id: roomId,
                name: "Chat with \(friend.displayName)",
                createdBy: userId,
                participants: [userId, friend.id],
                memberCount: 2,
                isPrivate: true,
                type: roomType,
                messageLifetime: messageLifetime
            )
            if !myRooms.contains(where: { $0.id == room.id }) {
                repository.addRoomOptimistically(room)
            }
            return room
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: AppLogger.shared.friendlyError(error))
            return nil
        }
    }

    func approve(_ request: FriendRequest) async {
        guard !userId.isEmpty else { return }

        do {
            let roomId = try await convexAPI.approveDirectRequest(userId: userId, requesterId: request.user.id)
            if let roomId {
                let room = ChatRoom(
                    id: roomId,
                    name: "Chat with \(request.user.displayName)",
                    createdBy: request.user.id,
                    participants: [userId, request.user.id],
                    memberCount: 2,
                    isPrivate: true,
                    type: request.roomType,
                    messageLifetime: request.messageLifetime
                )
                repository.addRoomOptimistically(room)
                NavigationStateManager.shared.navigateToRoom(room)
            }
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: AppLogger.shared.friendlyError(error))
        }
    }

    func removeFriend(_ friend: ChatUser) async {
        guard !userId.isEmpty else { return }
        do {
            try await convexAPI.removeFriend(userId: userId, friendId: friend.id)
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: AppLogger.shared.friendlyError(error))
        }
    }

    func reject(_ request: FriendRequest) async {
        guard !userId.isEmpty else { return }

        do {
            try await convexAPI.rejectDirectRequest(userId: userId, requesterId: request.user.id)
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: AppLogger.shared.friendlyError(error))
        }
    }

    func cancelRequest(_ request: FriendRequest) async {
        guard !userId.isEmpty else { return }

        do {
            try await convexAPI.cancelDirectRequest(userId: userId, friendId: request.user.id)
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: AppLogger.shared.friendlyError(error))
        }
    }

    // MARK: - Auth

    func signOut() {
        ConvexAuthService.shared.signOut()
    }

    // MARK: - Computed

    var totalPendingRequestCount: Int {
        incomingRequests.count + outgoingRequests.count
    }

    func sectionSummary(for section: Section) -> String {
        switch section {
        case .chats:
            "^[\(myRooms.count) Active Room](inflect: true)"
        case .friends:
            "^[\(friends.count) Friend](inflect: true)"
        case .requests:
            "^[\(totalPendingRequestCount) Pending Request](inflect: true)"
        }
    }

    // MARK: - Room Helpers

    func addRoomOptimistically(_ room: ChatRoom) {
        repository.addRoomOptimistically(room)
    }

    func removeRoomOptimistically(_ roomId: String) {
        repository.removeRoomOptimistically(roomId)
    }

    func clearUnread(for roomId: String) {
        repository.markRoomAsRead(roomId: roomId)
    }

    func typingText(for roomId: String) -> String? {
        guard let names = roomListTyping[roomId], !names.isEmpty else { return nil }
        switch names.count {
        case 1:  return "\(names[0]) is typing…"
        case 2:  return "\(names[0]) and \(names[1]) are typing…"
        default: return "\(names[0]) and \(names.count - 1) others are typing…"
        }
    }
}
