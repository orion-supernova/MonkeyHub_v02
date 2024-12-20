import SwiftUI

@MainActor
class NewChatViewModel: ObservableObject {
    @Published private(set) var users: [ChatUser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isCreating = false

    private let cloudKit: CloudKitManager

    init(cloudKit: CloudKitManager = .shared) {
        self.cloudKit = cloudKit
    }

    func fetchUsers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            users = try await cloudKit.fetchUsers()
        } catch {
            AlertManager.shared.showAlert(
                title: "Error",
                message: "Failed to load users: \(error.localizedDescription)"
            )
        }
    }

    func createRoom(name: String, participants: [ChatUser]) async throws {
        isCreating = true
        defer { isCreating = false }

        do {
            _ = try await cloudKit.createChatRoom(
                name: name,
                participants: participants
            )
        } catch {
            AlertManager.shared.showAlert(
                title: "Error",
                message: "Failed to create chat room: \(error.localizedDescription)"
            )
            throw error
        }
    }
}
