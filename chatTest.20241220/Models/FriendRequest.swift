import Foundation

struct FriendRequest: Identifiable, Hashable {
    let id: String
    let user: ChatUser
    let roomType: RoomType
    let messageLifetime: TimeInterval?
    let initialMessage: String
    let messageCount: Int
    let createdAt: Date
    var messages: [FriendRequestMessage] = []

    var hasMessages: Bool { messageCount > 0 || !initialMessage.isEmpty }
}
