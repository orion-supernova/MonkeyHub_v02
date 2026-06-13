import Foundation

/// A user this account has blocked. Returned by `users:listBlocked`.
struct BlockedUser: Identifiable, Hashable {
    let id: String
    let username: String
    let name: String
    let avatarStorageId: String?

    var displayName: String { name.isEmpty ? username : name }
    var displayInitial: String { displayName.prefix(1).uppercased() }
}
