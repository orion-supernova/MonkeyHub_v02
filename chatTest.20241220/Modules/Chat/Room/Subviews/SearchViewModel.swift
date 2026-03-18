import Foundation
import SwiftUI
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchMode: SearchMode = .rooms
    @Published private(set) var rooms: [ChatRoom] = []
    @Published private(set) var users: [ChatUser] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?
    @Published private(set) var joinedRoomIds: Set<String> = []

    private let convexAPI = ConvexChatAPI.shared
    private var searchCancellable: AnyCancellable?

    enum SearchMode: String, CaseIterable {
        case rooms = "Rooms"
        case users = "Users"

        var icon: String {
            switch self {
            case .rooms: return "bubble.left.and.bubble.right"
            case .users: return "person.2"
            }
        }
    }

    init() {
        // Debounced real-time search — fires 300ms after the user stops typing
        searchCancellable = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.search() }
            }
    }

    func setSearchMode(_ mode: SearchMode) {
        searchMode = mode
        clearResults()
        if !searchText.isEmpty {
            Task { await search() }
        }
    }

    func search() async {
        guard !searchText.isEmpty else { clearResults(); return }
        isSearching = true
        errorMessage = nil
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""

        do {
            switch searchMode {
            case .rooms:
                let allPublic = try await convexAPI.fetchPublicRooms()
                let joinedIdsFromRepository = Set(ChatRepository.shared.rooms.map(\.id))
                if joinedIdsFromRepository.isEmpty {
                    let joinedRooms = try await convexAPI.fetchUserRooms(userId: userId)
                    joinedRoomIds = Set(joinedRooms.map(\.id))
                } else {
                    joinedRoomIds = joinedIdsFromRepository
                }
                rooms = allPublic.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            case .users:
                users = try await convexAPI.searchUsers(query: searchText, currentUserId: userId)
            }
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }

        isSearching = false
    }

    func clearSearch() {
        searchText = ""
        clearResults()
        errorMessage = nil
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    private func clearResults() {
        rooms = []
        users = []
        joinedRoomIds = []
    }

    func isRoomJoined(_ room: ChatRoom) -> Bool {
        return joinedRoomIds.contains(room.id)
    }
}
