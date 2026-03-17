import Foundation
import ConvexMobile

// MARK: - Convex Document Response Types

/// Raw Convex room document returned by rooms:listUserRooms / rooms:getRoom
struct ConvexRoomDoc: Decodable {
    let _id: String
    let name: String
    let description: String?
    let createdBy: String
    let createdAt: Double
    let isPrivate: Bool
    let memberCount: Int
    let type: String?
    let messageLifetime: Double?
    let lastMessage: String?
    let lastMessageTime: Double?
    let avatarStorageId: String?
    let participantIds: [String]?  // injected by listUserRooms

    func toChatRoom() -> ChatRoom {
        ChatRoom(
            id: _id,
            name: name,
            createdBy: createdBy,
            createdAt: Date(timeIntervalSince1970: createdAt / 1000),
            lastMessage: lastMessage,
            lastMessageDate: lastMessageTime.map { Date(timeIntervalSince1970: $0 / 1000) },
            participants: participantIds ?? [],
            description: description,
            isPrivate: isPrivate,
            type: RoomType(rawValue: type ?? "Regular Room") ?? .regular,
            messageLifetime: messageLifetime,
            avatarStorageId: avatarStorageId,
            avatarURL: nil
        )
    }
}

/// Raw Convex message document returned by messages:list / listSince / listBefore
struct ConvexMessageDoc: Decodable {
    let _id: String
    let roomId: String
    let userId: String
    let content: String
    let createdAt: Double
    let type: String?
    let mediaStorageId: String?
    let senderName: String?
    let edited: Bool?
    let username: String?
    let name: String?

    func toChatMessage() -> ChatMessage {
        ChatMessage(
            id: _id,
            senderId: userId,
            senderName: senderName ?? name ?? username ?? "Unknown",
            content: content,
            type: MessageType(rawValue: type ?? "text") ?? .text,
            timestamp: Date(timeIntervalSince1970: createdAt / 1000),
            roomId: roomId,
            mediaStorageId: mediaStorageId,
            assetURL: nil,
            status: .sent,
            reactions: []
        )
    }
}

/// Raw Convex reaction document
struct ConvexReactionDoc: Decodable {
    let _id: String
    let messageId: String
    let userId: String
    let emoji: String
    let createdAt: Double

    func toMessageReaction() -> MessageReaction {
        MessageReaction(
            id: _id,
            emoji: emoji,
            userId: userId,
            messageId: messageId,
            timestamp: Date(timeIntervalSince1970: createdAt / 1000)
        )
    }
}

/// Typing user returned by typing:getTypingUsers
struct ConvexTypingUser: Decodable {
    let userId: String
    let name: String
    let username: String

    func toTypingIndicator(roomId: String) -> TypingIndicator {
        TypingIndicator(roomId: roomId, userId: userId, userName: name)
    }
}

/// User document returned by users:getProfile / users:searchUsers
struct ConvexUserDoc: Decodable {
    let _id: String
    let username: String
    let name: String?
    let email: String?
    let bio: String?
    let avatarStorageId: String?
    let status: String?
    let deviceTokens: [String]?

    func toChatUser() -> ChatUser {
        ChatUser(
            id: _id,
            name: name,
            username: username,
            email: email ?? "",
            avatarStorageId: avatarStorageId,
            bio: bio,
            deviceTokens: deviceTokens
        )
    }
}

// MARK: - Convex Chat API

/// All Convex chat operations. Replaces CloudKitManager as the data transport layer.
/// ChatRepository uses this instead of CloudKitManager.
final class ConvexChatAPI {
    static let shared = ConvexChatAPI()

    private let convex = ConvexService.shared

    private init() {}

    // MARK: - Rooms

    func fetchUserRooms(userId: String) async throws -> [ChatRoom] {
        let docs: [ConvexRoomDoc] = try await convex.queryOnce("rooms:listUserRooms", with: ["userId": userId])
        return docs.map { $0.toChatRoom() }
    }

    func fetchRoom(roomId: String) async throws -> ChatRoom? {
        let doc: ConvexRoomDoc? = try await convex.queryOnce("rooms:getRoom", with: ["roomId": roomId])
        return doc?.toChatRoom()
    }

    func fetchPublicRooms() async throws -> [ChatRoom] {
        let docs: [ConvexRoomDoc] = try await convex.queryOnce("rooms:listPublic")
        return docs.map { $0.toChatRoom() }
    }

    func createRoom(
        name: String,
        userId: String,
        description: String? = nil,
        isPrivate: Bool = true,
        type: RoomType = .regular,
        messageLifetime: TimeInterval? = nil,
        passwordHash: String? = nil
    ) async throws -> String {
        let roomId: String = try await convex.mutation("rooms:create", with: [
            "name": name,
            "userId": userId,
            "description": description,
            "isPrivate": isPrivate,
            "type": type.rawValue,
            "messageLifetime": messageLifetime,
            "passwordHash": passwordHash
        ])
        return roomId
    }

    func joinRoom(roomId: String, userId: String, passwordHash: String? = nil) async throws {
        try await convex.mutationVoid("rooms:join", with: [
            "roomId": roomId,
            "userId": userId,
            "passwordHash": passwordHash
        ])
    }

    func leaveRoom(roomId: String, userId: String) async throws {
        try await convex.mutationVoid("rooms:leave", with: ["roomId": roomId, "userId": userId])
    }

    func deleteRoom(roomId: String, userId: String) async throws {
        try await convex.mutationVoid("rooms:deleteRoom", with: ["roomId": roomId, "userId": userId])
    }

    func updateRoom(roomId: String, userId: String, name: String, description: String?, isPrivate: Bool? = nil) async throws {
        try await convex.mutationVoid("rooms:updateRoom", with: [
            "roomId": roomId,
            "userId": userId,
            "name": name,
            "description": description,
            "isPrivate": isPrivate
        ])
    }

    func fetchRoomMembers(roomId: String) async throws -> [ChatUser] {
        let docs: [ConvexUserDoc] = try await convex.queryOnce("rooms:getMembers", with: ["roomId": roomId])
        return docs.map { $0.toChatUser() }
    }

    func getOrCreateDM(userId: String, friendId: String) async throws -> String {
        let roomId: String = try await convex.mutation("rooms:getOrCreateDM", with: [
            "userId": userId,
            "friendId": friendId
        ])
        return roomId
    }

    // MARK: - Messages

    func fetchMessages(roomId: String, limit: Int = 50) async throws -> [ChatMessage] {
        let docs: [ConvexMessageDoc] = try await convex.queryOnce("messages:list", with: [
            "roomId": roomId,
            "limit": Double(limit)
        ])
        return docs.map { $0.toChatMessage() }
    }

    func fetchMessagesSince(roomId: String, since: Date) async throws -> [ChatMessage] {
        let docs: [ConvexMessageDoc] = try await convex.queryOnce("messages:listSince", with: [
            "roomId": roomId,
            "since": since.timeIntervalSince1970 * 1000
        ])
        return docs.map { $0.toChatMessage() }
    }

    func fetchMessagesBefore(roomId: String, before: Date, limit: Int = 30) async throws -> [ChatMessage] {
        let docs: [ConvexMessageDoc] = try await convex.queryOnce("messages:listBefore", with: [
            "roomId": roomId,
            "beforeTimestamp": before.timeIntervalSince1970 * 1000,
            "limit": Double(limit)
        ])
        return docs.map { $0.toChatMessage() }
    }

    func sendMessage(
        roomId: String,
        userId: String,
        content: String,
        type: MessageType = .text,
        senderName: String,
        mediaStorageId: String? = nil
    ) async throws -> String {
        var args: [String: ConvexEncodable?] = [
            "roomId": roomId,
            "userId": userId,
            "content": content,
            "type": type.rawValue,
            "senderName": senderName,
        ]
        if let mediaStorageId {
            args["mediaStorageId"] = mediaStorageId
        }
        let messageId: String = try await convex.mutation("messages:send", with: args)
        return messageId
    }

    func deleteMessage(messageId: String, userId: String) async throws {
        try await convex.mutationVoid("messages:deleteMessage", with: [
            "messageId": messageId,
            "userId": userId
        ])
    }

    // MARK: - Reactions

    func addReaction(messageId: String, userId: String, emoji: String) async throws -> String {
        let reactionId: String = try await convex.mutation("reactions:addReaction", with: [
            "messageId": messageId,
            "userId": userId,
            "emoji": emoji
        ])
        return reactionId
    }

    func removeReaction(messageId: String, userId: String, emoji: String) async throws {
        try await convex.mutationVoid("reactions:removeReaction", with: [
            "messageId": messageId,
            "userId": userId,
            "emoji": emoji
        ])
    }

    func fetchReactions(for messageId: String) async throws -> [MessageReaction] {
        let docs: [ConvexReactionDoc] = try await convex.queryOnce("reactions:getReactions", with: ["messageId": messageId])
        return docs.map { $0.toMessageReaction() }
    }

    func fetchReactions(for messageIds: [String]) async throws -> [String: [MessageReaction]] {
        guard !messageIds.isEmpty else { return [:] }
        // Convex requires array of IDs as ConvexEncodable
        let ids: [ConvexEncodable?] = messageIds.map { $0 as ConvexEncodable? }
        let raw: [String: [ConvexReactionDoc]] = try await convex.queryOnce(
            "reactions:getReactionsForMessages",
            with: ["messageIds": ids as ConvexEncodable?]
        )
        return raw.mapValues { $0.map { $0.toMessageReaction() } }
    }

    // MARK: - Typing Indicators

    func setTyping(roomId: String, userId: String) async throws {
        try await convex.mutationVoid("typing:setTyping", with: ["roomId": roomId, "userId": userId])
    }

    func clearTyping(roomId: String, userId: String) async throws {
        try await convex.mutationVoid("typing:clearTyping", with: ["roomId": roomId, "userId": userId])
    }

    func fetchTypingUsers(roomId: String, currentUserId: String) async throws -> [TypingIndicator] {
        let users: [ConvexTypingUser] = try await convex.queryOnce(
            "typing:getTypingUsers",
            with: ["roomId": roomId, "currentUserId": currentUserId]
        )
        return users.map { $0.toTypingIndicator(roomId: roomId) }
    }

    // MARK: - Users

    func fetchUser(userId: String) async throws -> ChatUser? {
        let doc: ConvexUserDoc? = try await convex.queryOnce("users:getProfile", with: ["userId": userId])
        return doc?.toChatUser()
    }

    func updateUserProfile(userId: String, name: String, email: String?, bio: String?) async throws {
        try await convex.mutationVoid("users:updateProfile", with: [
            "userId": userId,
            "name": name,
            "email": email,
            "bio": bio
        ])
    }

    func updateUserAvatar(userId: String, storageId: String) async throws {
        try await convex.mutationVoid("users:updateAvatar", with: [
            "userId": userId,
            "avatarStorageId": storageId
        ])
    }

    func updateRoomAvatar(roomId: String, storageId: String) async throws {
        try await convex.mutationVoid("rooms:updateRoomAvatar", with: [
            "roomId": roomId,
            "avatarStorageId": storageId
        ])
    }

    func searchUsers(query: String, currentUserId: String) async throws -> [ChatUser] {
        let docs: [ConvexUserDoc] = try await convex.queryOnce("users:searchUsers", with: [
            "query": query,
            "currentUserId": currentUserId
        ])
        return docs.map { $0.toChatUser() }
    }

    // MARK: - File Storage

    /// Returns a one-time upload URL. Client PUTs the file to this URL, then uses the storageId.
    func generateUploadURL() async throws -> String {
        let url: String = try await convex.mutation("files:generateUploadUrl")
        return url
    }

    func getFileURL(storageId: String) async throws -> String? {
        let url: String? = try await convex.queryOnce("files:getFileUrl", with: ["storageId": storageId])
        return url
    }

    func deleteFile(storageId: String) async throws {
        try await convex.mutationVoid("files:deleteFile", with: ["storageId": storageId])
    }

    /// Upload data to Convex file storage. Returns the storageId.
    func uploadFile(data: Data, mimeType: String) async throws -> String {
        // 1. Get upload URL
        let uploadURL = try await generateUploadURL()

        // 2. Extract storageId from the URL (it's the last path component)
        guard let url = URL(string: uploadURL) else {
            throw ConvexError.serverError("Invalid upload URL")
        }

        // 3. PUT the file data
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ConvexError.serverError("Upload failed")
        }

        // Convex storage response contains the storageId
        struct UploadResponse: Decodable { let storageId: String }
        let result = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        return result.storageId
    }
}
