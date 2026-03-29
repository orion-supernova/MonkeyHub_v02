import Foundation

struct MessageReaction: Identifiable, Codable, Equatable {
    let id: String
    let emoji: String
    let userId: String
    let messageId: String
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        emoji: String,
        userId: String,
        messageId: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.emoji = MessageReaction.normalizeEmoji(emoji)
        self.messageId = messageId
        self.timestamp = timestamp
    }

    static func == (lhs: MessageReaction, rhs: MessageReaction) -> Bool { lhs.id == rhs.id }

    static func normalizeEmoji(_ value: String) -> String {
        let stripped = value.replacingOccurrences(of: "\u{FE0E}", with: "")
        switch stripped {
        case "❤": return "❤️"
        default: return stripped
        }
    }
}

/// Aggregated reactions for UI display
struct ReactionGroup: Identifiable {
    let emoji: String
    let reactions: [MessageReaction]

    var id: String { emoji }
    var count: Int { reactions.count }
    var userIds: Set<String> { Set(reactions.map { $0.userId }) }

    func containsUser(_ userId: String) -> Bool { userIds.contains(userId) }
}
