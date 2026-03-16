import Foundation

/// Represents an ephemeral typing state for a user in a chat room.
struct TypingIndicator: Identifiable, Equatable {
    let id: String          // roomId_userId
    let roomId: String
    let userId: String
    let userName: String
    let timestamp: Date
    let expiresAt: Date

    init(roomId: String, userId: String, userName: String) {
        self.id = "\(roomId)_\(userId)"
        self.roomId = roomId
        self.userId = userId
        self.userName = userName
        self.timestamp = Date()
        self.expiresAt = Date().addingTimeInterval(5)
    }

    var isExpired: Bool { Date() > expiresAt }

    static func == (lhs: TypingIndicator, rhs: TypingIndicator) -> Bool { lhs.id == rhs.id }
}
