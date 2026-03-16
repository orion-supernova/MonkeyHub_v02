import SwiftUI
import Combine

@MainActor
class ChatListViewModel: ObservableObject {
    @Published var myRooms: [ChatRoom] = []
    @Published var unreadCounts: [String: Int] = [:]
    @Published var isLoading = false
    
    private let repository = ChatRepository.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("🎬 ChatListViewModel init")
        setupBindings()
    }
    
    deinit {
        print("💀 ChatListViewModel deinit")
    }
    
    private func setupBindings() {
        // Bind to Repository rooms
        repository.$rooms
            .receive(on: DispatchQueue.main)
            .assign(to: \.myRooms, on: self)
            .store(in: &cancellables)
            
        // Bind to Repository unread counts
        repository.$unreadCounts
            .receive(on: DispatchQueue.main)
            .assign(to: \.unreadCounts, on: self)
            .store(in: &cancellables)
    }
    
    func loadRooms() async {
        isLoading = true
        await repository.fetchRooms()
        isLoading = false
    }

    func addRoomOptimistically(_ room: ChatRoom) {
        // Single source of truth: repository publishes room changes back to this ViewModel.
        repository.addRoomOptimistically(room)
    }

    func removeRoomOptimistically(_ roomId: String) {
        // Single source of truth: repository publishes room changes back to this ViewModel.
        repository.removeRoomOptimistically(roomId)
    }

    func clearUnread(for roomId: String) {
        // In the future, this should also tell Repo to clear it potentially
        unreadCounts[roomId] = 0
    }
}
