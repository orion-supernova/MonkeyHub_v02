import CloudKit
import Foundation
import SwiftUI

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchMode: SearchMode = .rooms
    @Published private(set) var rooms: [ChatRoom] = []
    @Published private(set) var users: [ChatUser] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?
    @Published private(set) var joinedRoomIds: Set<String> = []

    private let cloudKit = CloudKitManager.shared

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

    func setSearchMode(_ mode: SearchMode) {
        searchMode = mode
        clearResults()
        
        if !searchText.isEmpty {
            Task {
                await search()
            }
        }
    }

    func search() async {
        guard !searchText.isEmpty else {
            clearResults()
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            switch searchMode {
            case .rooms:
                rooms = try await searchPublicRooms(query: searchText)
            case .users:
                users = try await cloudKit.searchUsers(matching: searchText)
            }
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }

        isSearching = false
    }
    
    private func searchPublicRooms(query: String) async throws -> [ChatRoom] {
        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""
        
        // Fetch all public rooms (isPrivate == false)
        let predicate = NSPredicate(
            format: "(%K == NO)",
            ChatRoom.isPrivateKey
        )
        
        let ckQuery = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)
        ckQuery.sortDescriptors = [NSSortDescriptor(key: ChatRoom.createdAtKey, ascending: false)]
        
        let (records, _) = try await cloudKit.database.records(matching: ckQuery)
        let rooms = try records.compactMap { try ChatRoom(from: try $0.1.get()) }
        
        // Track which rooms the user has already joined
        joinedRoomIds = Set(rooms.filter { $0.participants.contains(userId) }.map { $0.id })
        
        // Filter by search query
        return rooms.filter { room in
            room.name.localizedCaseInsensitiveContains(query)
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

    private func clearResults() {
        rooms = []
        users = []
        joinedRoomIds = []
    }
    
    func isRoomJoined(_ room: ChatRoom) -> Bool {
        return joinedRoomIds.contains(room.id)
    }
}