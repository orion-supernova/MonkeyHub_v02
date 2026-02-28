import Foundation
import CloudKit

/// Service responsible for managing message reactions
@MainActor
class ReactionService {
    static let shared = ReactionService()
    
    private let cloudKit = CloudKitManager.shared
    private let chatRepository = ChatRepository.shared
    private let userIdKey = "userId"
    
    private init() {}
    
    /// Fetch all reactions for a message
    /// - Parameter messageId: The message ID
    /// - Returns: Array of reactions
    func fetchReactions(for messageId: String) async throws -> [MessageReaction] {
        print("🔍 ReactionService: Fetching reactions for message \(messageId)")

        let predicate = NSPredicate(format: "%K == %@", MessageReaction.messageIdKey, messageId)
        let query = CKQuery(recordType: MessageReaction.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: MessageReaction.timestampKey, ascending: true)]

        do {
            var allReactions: [MessageReaction] = []
            var cursor: CKQueryOperation.Cursor?

            // First page
            let (records, firstCursor) = try await cloudKit.database.records(matching: query)
            allReactions.append(contentsOf: decodeReactions(from: records))
            cursor = firstCursor

            // Follow pagination cursor
            while let activeCursor = cursor {
                let (moreRecords, nextCursor) = try await cloudKit.database.records(continuingMatchFrom: activeCursor)
                allReactions.append(contentsOf: decodeReactions(from: moreRecords))
                cursor = nextCursor
            }

            print("✅ ReactionService: Found \(allReactions.count) reactions for message \(messageId)")
            return allReactions
        } catch let error as CKError where error.code == .unknownItem {
            print("ℹ️ ReactionService: MessageReaction record type not found (expected on first use)")
            return []
        } catch {
            print("❌ ReactionService: Error fetching reactions: \(error)")
            throw error
        }
    }

    /// Fetch reactions for multiple messages at once
    /// - Parameter messageIds: Array of message IDs
    /// - Returns: Dictionary mapping messageId to reactions array
    func fetchReactions(for messageIds: [String]) async throws -> [String: [MessageReaction]] {
        guard !messageIds.isEmpty else { return [:] }

        print("🔍 ReactionService: Fetching reactions for \(messageIds.count) messages")

        let predicate = NSPredicate(format: "%K IN %@", MessageReaction.messageIdKey, messageIds)
        let query = CKQuery(recordType: MessageReaction.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: MessageReaction.timestampKey, ascending: true)]

        do {
            var allReactions: [MessageReaction] = []
            var cursor: CKQueryOperation.Cursor?

            // First page
            let (records, firstCursor) = try await cloudKit.database.records(matching: query)
            allReactions.append(contentsOf: decodeReactions(from: records))
            cursor = firstCursor

            // Follow pagination cursor
            while let activeCursor = cursor {
                let (moreRecords, nextCursor) = try await cloudKit.database.records(continuingMatchFrom: activeCursor)
                allReactions.append(contentsOf: decodeReactions(from: moreRecords))
                cursor = nextCursor
            }

            print("✅ ReactionService: Found \(allReactions.count) total reactions")

            let grouped = Dictionary(grouping: allReactions, by: { $0.messageId })
            return grouped
        } catch let error as CKError where error.code == .unknownItem {
            print("ℹ️ ReactionService: MessageReaction record type not found (expected on first use)")
            return [:]
        } catch {
            print("❌ ReactionService: Error fetching reactions: \(error)")
            throw error
        }
    }

    /// Decode reaction records resiliently — one bad record won't kill the entire batch
    private func decodeReactions(from records: [(CKRecord.ID, Result<CKRecord, Error>)]) -> [MessageReaction] {
        records.compactMap { _, result in
            guard let record = try? result.get(),
                  let reaction = try? MessageReaction(from: record) else {
                print("⚠️ ReactionService: Skipping undecodable reaction record")
                return nil
            }
            return reaction
        }
    }
    
    /// Add a reaction to a message
    /// - Parameters:
    ///   - emoji: The emoji to add as a reaction
    ///   - messageId: The ID of the message to react to
    ///   - roomId: The room ID containing the message
    func addReaction(emoji: String, to messageId: String, in roomId: String) async throws {
        guard let userId = UserDefaults.standard.string(forKey: userIdKey) else {
            print("❌ ReactionService: User not logged in")
            throw ReactionError.userNotFound
        }
        
        print("➕ ReactionService: Adding reaction \(emoji) to message \(messageId)")
        
        // Check if user already reacted with this emoji
        let existingReactions = try await fetchReactions(for: messageId)
        if existingReactions.contains(where: { $0.userId == userId && $0.emoji == emoji }) {
            print("⚠️ ReactionService: User already reacted with \(emoji)")
            return
        }
        
        // Create new reaction
        let reaction = MessageReaction(
            emoji: emoji,
            userId: userId,
            messageId: messageId
        )
        
        // Save to CloudKit
        do {
            let record = reaction.toRecord()
            _ = try await cloudKit.database.save(record)
            
            print("✅ ReactionService: Saved reaction to CloudKit")
            
            // Update local message
            if let messageIndex = chatRepository.activeRoomMessages.firstIndex(where: { $0.id == messageId }) {
                chatRepository.activeRoomMessages[messageIndex].reactions.append(reaction)
                print("✅ ReactionService: Updated local message with reaction")
            } else {
                print("⚠️ ReactionService: Message not found in active room messages")
            }
        } catch let error as CKError {
            // If messageReference field doesn't exist, that's okay - messageId field will work
            if error.code == .invalidArguments && error.localizedDescription.contains("messageReference") {
                print("⚠️ ReactionService: messageReference field not in schema, using messageId only")
                
                // Create record without reference field
                let recordID = CKRecord.ID(recordName: reaction.id)
                let record = CKRecord(recordType: MessageReaction.recordType, recordID: recordID)
                
                record[MessageReaction.idKey] = reaction.id
                record[MessageReaction.emojiKey] = reaction.emoji
                record[MessageReaction.userIdKey] = reaction.userId
                record[MessageReaction.messageIdKey] = reaction.messageId
                record[MessageReaction.timestampKey] = reaction.timestamp
                
                _ = try await cloudKit.database.save(record)
                
                print("✅ ReactionService: Saved reaction to CloudKit (without reference)")
                
                // Update local message
                if let messageIndex = chatRepository.activeRoomMessages.firstIndex(where: { $0.id == messageId }) {
                    chatRepository.activeRoomMessages[messageIndex].reactions.append(reaction)
                    print("✅ ReactionService: Updated local message with reaction")
                }
            } else {
                throw error
            }
        }
    }
    
    /// Remove a reaction from a message
    /// - Parameters:
    ///   - reactionId: The ID of the reaction to remove
    ///   - messageId: The ID of the message
    ///   - roomId: The room ID containing the message
    func removeReaction(reactionId: String, from messageId: String, in roomId: String) async throws {
        guard let userId = UserDefaults.standard.string(forKey: userIdKey) else {
            print("❌ ReactionService: User not logged in")
            throw ReactionError.userNotFound
        }
        
        print("➖ ReactionService: Removing reaction \(reactionId) from message \(messageId)")
        
        // Verify ownership before deletion
        let recordID = CKRecord.ID(recordName: reactionId)
        let record = try await cloudKit.database.record(for: recordID)
        
        guard let recordUserId = record[MessageReaction.userIdKey] as? String,
              recordUserId == userId else {
            print("❌ ReactionService: Unauthorized to remove this reaction")
            throw ReactionError.unauthorized
        }
        
        // Delete from CloudKit
        try await cloudKit.database.deleteRecord(withID: recordID)
        
        print("✅ ReactionService: Deleted reaction from CloudKit")
        
        // Update local message
        if let messageIndex = chatRepository.activeRoomMessages.firstIndex(where: { $0.id == messageId }) {
            chatRepository.activeRoomMessages[messageIndex].reactions.removeAll { $0.id == reactionId }
            print("✅ ReactionService: Updated local message (removed reaction)")
        } else {
            print("⚠️ ReactionService: Message not found in active room messages")
        }
    }
    
    /// Toggle a reaction (add if not present, remove if present)
    /// - Parameters:
    ///   - emoji: The emoji to toggle
    ///   - messageId: The ID of the message
    ///   - roomId: The room ID containing the message
    func toggleReaction(emoji: String, on messageId: String, in roomId: String) async throws {
        guard let userId = UserDefaults.standard.string(forKey: userIdKey) else {
            print("❌ ReactionService: User not logged in")
            throw ReactionError.userNotFound
        }
        
        print("🔄 ReactionService: Toggling reaction \(emoji) on message \(messageId)")
        
        // Find existing reaction
        let existingReactions = try await fetchReactions(for: messageId)
        
        if let existingReaction = existingReactions.first(where: { $0.userId == userId && $0.emoji == emoji }) {
            // Remove reaction
            print("🔄 ReactionService: Found existing reaction, removing it")
            try await removeReaction(reactionId: existingReaction.id, from: messageId, in: roomId)
        } else {
            // Add reaction
            print("🔄 ReactionService: No existing reaction found, adding new one")
            try await addReaction(emoji: emoji, to: messageId, in: roomId)
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
        case .userNotFound:
            return "User not found"
        case .messageNotFound:
            return "Message not found"
        case .reactionNotFound:
            return "Reaction not found"
        case .unauthorized:
            return "Unauthorized to remove this reaction"
        }
    }
}