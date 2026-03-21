import Foundation

struct FriendRequestMessage: Identifiable, Hashable {
    let id: String
    let userId: String
    let content: String
    let createdAt: Date
}
