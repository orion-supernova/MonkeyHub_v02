import Foundation

struct DraftDirectChatSession: Identifiable, Hashable {
    let id: String
    let user: ChatUser
    let roomType: RoomType
    let messageLifetime: TimeInterval?
    let requestId: String?

    init(user: ChatUser, roomType: RoomType, messageLifetime: TimeInterval?, requestId: String? = nil) {
        self.user = user
        self.roomType = roomType
        self.messageLifetime = messageLifetime
        self.requestId = requestId
        self.id = "draft:\(user.id):\(roomType.rawValue):\(messageLifetime ?? 0):\(requestId ?? "new")"
    }
}
