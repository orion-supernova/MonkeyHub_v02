import Foundation

/// Service responsible for managing message reactions via Convex.
@MainActor
class ReactionService {
    static let shared = ReactionService()

    private let convexAPI = ConvexChatAPI.shared
    private let chatRepository = ChatRepository.shared
    private let userIdKey = "userId"

    private init() {}

    /// Add a reaction to a message (idempotent — Convex deduplicates server-side).
    func addReaction(emoji: String, to messageId: String, in roomId: String) async throws {
        guard let userId = UserDefaults.standard.string(forKey: userIdKey) else {
            throw ReactionError.userNotFound
        }
        let normalizedEmoji = MessageReaction.normalizeEmoji(emoji)
        _ = try await convexAPI.addReaction(messageId: messageId, userId: userId, emoji: normalizedEmoji)

        // Optimistic local update — must use full array replacement to trigger @Published
        var messages = chatRepository.activeRoomMessages
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            let alreadyExists = messages[idx].reactions
                .contains { $0.userId == userId && $0.emoji == normalizedEmoji }
            if !alreadyExists {
                let reaction = MessageReaction(emoji: normalizedEmoji, userId: userId, messageId: messageId)
                messages[idx].reactions.append(reaction)
                chatRepository.activeRoomMessages = messages
            }
        }
    }

    /// Remove a reaction from a message.
    func removeReaction(emoji: String, from messageId: String, in roomId: String) async throws {
        guard let userId = UserDefaults.standard.string(forKey: userIdKey) else {
            throw ReactionError.userNotFound
        }
        let normalizedEmoji = MessageReaction.normalizeEmoji(emoji)
        try await convexAPI.removeReaction(messageId: messageId, userId: userId, emoji: normalizedEmoji)

        // Optimistic local update — must use full array replacement to trigger @Published
        var messages = chatRepository.activeRoomMessages
        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
            messages[idx].reactions.removeAll { $0.userId == userId && $0.emoji == normalizedEmoji }
            chatRepository.activeRoomMessages = messages
        }
    }

    /// Toggle a reaction: add if not present, remove if present.
    func toggleReaction(emoji: String, on messageId: String, in roomId: String) async throws {
        guard let userId = UserDefaults.standard.string(forKey: userIdKey) else {
            throw ReactionError.userNotFound
        }
        let normalizedEmoji = MessageReaction.normalizeEmoji(emoji)
        let alreadyReacted = chatRepository.activeRoomMessages
            .first { $0.id == messageId }?
            .reactions
            .contains { $0.userId == userId && $0.emoji == normalizedEmoji } ?? false

        if alreadyReacted {
            try await removeReaction(emoji: normalizedEmoji, from: messageId, in: roomId)
        } else {
            try await addReaction(emoji: normalizedEmoji, to: messageId, in: roomId)
        }
    }
}

enum ReactionError: Error, LocalizedError {
    case userNotFound
    case messageNotFound
    case reactionNotFound
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .userNotFound:     return "User not found"
        case .messageNotFound:  return "Message not found"
        case .reactionNotFound: return "Reaction not found"
        case .unauthorized:     return "Unauthorized to remove this reaction"
        }
    }
}
