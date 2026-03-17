import SwiftUI
import Combine

@MainActor
class ChatListViewModel: ObservableObject {
    @Published var myRooms: [ChatRoom] = []
    @Published var unreadCounts: [String: Int] = [:]
    @Published var roomListTyping: [String: [String]] = [:]
    @Published var isLoading = false

    private let repository = ChatRepository.shared
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
    }

    func loadRooms() async {
        isLoading = true
        await repository.fetchRooms()
        isLoading = false
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
