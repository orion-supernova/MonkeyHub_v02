import Foundation

struct FriendRequest: Identifiable, Hashable {
    let id: String
    let user: ChatUser
    let roomType: RoomType
    let messageLifetime: TimeInterval?
    let initialMessage: String
    let createdAt: Date
    var messages: [FriendRequestMessage] = []
}
