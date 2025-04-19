import Combine
import SwiftUI

@MainActor
class ChatRoomListViewModel: ObservableObject {
    @Published private(set) var rooms: [ChatRoom] = []
    @Published private(set) var filteredRooms: [ChatRoom] = []
    @Published private(set) var isLoading = false
    @Published var error: Error?

    private var cancellables = Set<AnyCancellable>()
    private let cloudKit: CloudKitManager

    init(cloudKit: CloudKitManager = .shared) {
        self.cloudKit = cloudKit
        setupSubscriptions()
    }

    func fetchRooms() async {
        isLoading = true
        defer { isLoading = false }

        do {
            rooms = try await cloudKit.fetchUserRooms()
            filteredRooms = rooms
        } catch {
            self.error = error
            AlertManager.shared.showAlert(
                title: "Error",
                message: "Failed to load chat rooms: \(error.localizedDescription)"
            )
        }
    }

    func filterRooms(_ query: String) {
        if query.isEmpty {
            filteredRooms = rooms
        } else {
            filteredRooms = rooms.filter { room in
                room.name.localizedCaseInsensitiveContains(query)
                    || (room.lastMessage?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
    }

    private func setupSubscriptions() {
        // Subscribe to real-time updates
        // Implement CloudKit subscription handling
    }
}
