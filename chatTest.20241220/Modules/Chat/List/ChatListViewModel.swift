import CloudKit
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
        // Update local list immediately for instant UI feedback
        if !myRooms.contains(where: { $0.id == room.id }) {
            withAnimation {
                myRooms.insert(room, at: 0)
            }
        }
        // Also update repository for persistence
        repository.addRoomOptimistically(room)
    }

    func removeRoomOptimistically(_ roomId: String) {
        // Update local list immediately for instant UI feedback
        withAnimation {
            myRooms.removeAll { $0.id == roomId }
        }
        // Also update repository for persistence
        repository.removeRoomOptimistically(roomId)
    }

    func clearUnread(for roomId: String) {
        // In the future, this should also tell Repo to clear it potentially
        unreadCounts[roomId] = 0
    }
}
