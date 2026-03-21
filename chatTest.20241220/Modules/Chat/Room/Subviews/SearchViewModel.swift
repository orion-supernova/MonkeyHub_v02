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
    private var currentSearchTask: Task<Void, Never>?

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
        // Search fires 300ms after the user stops typing. Any new keystroke resets the timer,
        // and any in-flight search task from a previous term is cancelled before the new one starts.
        searchCancellable = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleSearch()
            }
    }

    deinit {
        currentSearchTask?.cancel()
    }

    // MARK: - Public Interface

    func setSearchMode(_ mode: SearchMode) {
        searchMode = mode
        clearResults()
        if !searchText.isEmpty {
            scheduleSearch()
        }
    }

    func clearSearch() {
        searchText = ""
        clearResults()
        errorMessage = nil
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    /// Called by the view on disappear. Cancels any in-flight search task and tears down
    /// the text subscription so no further work runs after the sheet is dismissed.
    func cleanup() {
        currentSearchTask?.cancel()
        currentSearchTask = nil
        searchCancellable = nil
    }

    func isRoomJoined(_ room: ChatRoom) -> Bool {
        joinedRoomIds.contains(room.id)
    }

    // MARK: - Private

    private func scheduleSearch() {
        // Cancel the previous task before starting a new one. This prevents concurrent
        // searches from piling up when the user types quickly, and ensures a cancelled
        // task releases its strong `self` reference so the ViewModel can deinit cleanly.
        currentSearchTask?.cancel()
        currentSearchTask = Task { await search() }
    }

    private func search() async {
        guard !searchText.isEmpty else { clearResults(); return }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""

        do {
            switch searchMode {
            case .rooms:
                let allPublic = try await convexAPI.fetchPublicRooms()
                guard !Task.isCancelled else { return }

                let joinedIdsFromRepository = Set(ChatRepository.shared.rooms.map(\.id))
                if joinedIdsFromRepository.isEmpty {
                    let joinedRooms = try await convexAPI.fetchUserRooms(userId: userId)
                    guard !Task.isCancelled else { return }
                    joinedRoomIds = Set(joinedRooms.map(\.id))
                } else {
                    joinedRoomIds = joinedIdsFromRepository
                }

                rooms = allPublic.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

            case .users:
                let result = try await convexAPI.searchUsers(query: searchText, currentUserId: userId)
                guard !Task.isCancelled else { return }
                users = result
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }

    private func clearResults() {
        rooms = []
        users = []
        joinedRoomIds = []
    }
}
