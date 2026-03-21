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

    func approve(_ request: FriendRequest) async {
        let userId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""
        guard !userId.isEmpty else { return }

        do {
            let roomId = try await convexAPI.approveDirectRequest(userId: userId, requesterId: request.user.id)
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
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: AppLogger.shared.friendlyError(error))
        }
    }

    func removeFriend(_ friend: ChatUser) async {
        let userId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""
        guard !userId.isEmpty else { return }
        do {
            try await convexAPI.removeFriend(userId: userId, friendId: friend.id)
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: AppLogger.shared.friendlyError(error))
        }
    }

    func reject(_ request: FriendRequest) async {
        let userId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""
        guard !userId.isEmpty else { return }

        do {
            try await convexAPI.rejectDirectRequest(userId: userId, requesterId: request.user.id)
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: AppLogger.shared.friendlyError(error))
        }
    }

    var totalPendingRequestCount: Int {
        incomingRequests.count + outgoingRequests.count
    }

    func addRoomOptimistically(_ room: ChatRoom) {
        repository.addRoomOptimistically(room)
    }

    func removeRoomOptimistically(_ roomId: String) {
        repository.removeRoomOptimistically(roomId)
    }

    func clearUnread(for roomId: String) {
        repository.markRoomAsRead(roomId: roomId)
    }

    /// Returns a human-readable typing string for the room list row, or nil if nobody is typing.
    func typingText(for roomId: String) -> String? {
        guard let names = roomListTyping[roomId], !names.isEmpty else { return nil }
        switch names.count {
        case 1:  return "\(names[0]) is typing…"
        case 2:  return "\(names[0]) and \(names[1]) are typing…"
        default: return "\(names[0]) and \(names.count - 1) others are typing…"
        }
    }
}
