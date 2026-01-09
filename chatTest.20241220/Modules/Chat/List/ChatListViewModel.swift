import CloudKit
import SwiftUI
import Combine

@MainActor
class ChatListViewModel: ObservableObject {
    @Published var myRooms: [ChatRoom] = []
    @Published var unreadCounts: [String: Int] = [:]
    
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
        await repository.fetchRooms()
    }
    
    func clearUnread(for roomId: String) {
        // In the future, this should also tell Repo to clear it potentially
        unreadCounts[roomId] = 0
    }
}
