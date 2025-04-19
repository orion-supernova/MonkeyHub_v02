import CloudKit
import Combine
import SwiftUI

@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var users: [ChatUser] = []
    @Published private(set) var rooms: [ChatRoom] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let cloudKit: CloudKitManager
    private var cancellables = Set<AnyCancellable>()

    init(cloudKit: CloudKitManager = .shared) {
        self.cloudKit = cloudKit
    }

    // Manual search trigger for use with the search button
    func search() async {
        await performSearch(query: searchText)
    }

    // Perform the actual search operation
    func performSearch(query: String) async {
        guard !query.isEmpty && query.count >= 2 else {
            rooms = []
            users = []
            errorMessage = query.isEmpty ? nil : "Search term must be at least 2 characters"
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            switch searchMode {
            case .rooms:
                rooms = try await cloudKit.searchRooms(matching: query)
                print("🔍 Found \(rooms.count) rooms:")
                rooms.forEach { room in
                    print("  • \(room.name) (\(room.participants.count) participants)")
                }
                users = []
            case .users:
                users = try await searchUsers(matching: query)
                print("🔍 Found \(users.count) users:")
                users.forEach { user in
                    print("  • \(user.name) (\(user.email))")
                }
                rooms = []
            }
        } catch let error as CKError {
            rooms = []
            users = []

            // Print raw CloudKit error details
            print("⚠️ SEARCH ERROR: \(error.code.rawValue)")
            print("📝 Error description: \(error.localizedDescription)")

            // Print server message if available
            if let serverMessage = error.errorUserInfo["CKErrorDescription"] as? String {
                print("🔍 SERVER MESSAGE: \(serverMessage)")
            }

            // Print the full error info for debugging
            print("📊 Full error details: \(error)")

            // Use direct server error message or fallback to localized description
            errorMessage =
                error.errorUserInfo["CKErrorDescription"] as? String ?? error.localizedDescription
        } catch {
            rooms = []
            users = []
            print("❓ UNEXPECTED ERROR: \(error)")
            errorMessage = error.localizedDescription
        }

        isSearching = false
    }

    private func searchUsers(matching query: String) async throws -> [ChatUser] {
        // Use CloudKit predicates to search on the server instead of fetching all users
        return try await cloudKit.searchUsers(matching: query)
    }

    // Current search mode
    @Published var searchMode: SearchMode = .rooms

    enum SearchMode: String, CaseIterable {
        case rooms = "Rooms"
        case users = "Users"

        var icon: String {
            switch self {
            case .rooms: return "bubble.left.and.bubble.right.fill"
            case .users: return "person.2.fill"
            }
        }
    }

    // Change search mode and clear previous results
    func setSearchMode(_ mode: SearchMode) {
        guard searchMode != mode else { return }
        searchMode = mode
        users = []
        rooms = []
    }

    // Clear search results and text
    func clearSearch() {
        searchText = ""
        users = []
        rooms = []
        errorMessage = nil
    }

    // Add method to clear error message
    func clearErrorMessage() {
        errorMessage = nil
    }
}
