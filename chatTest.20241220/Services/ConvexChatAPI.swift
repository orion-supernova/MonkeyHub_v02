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
    let hasPassword: Bool?         // returned by listPublic (stripped of actual hash)

    func toChatRoom() -> ChatRoom {
        ChatRoom(
            id: _id,
            name: name,
            createdBy: createdBy,
            createdAt: Date(timeIntervalSince1970: createdAt / 1000),
            lastMessage: lastMessage,
            lastMessageDate: lastMessageTime.map { Date(timeIntervalSince1970: $0 / 1000) },
            participants: participantIds ?? [],
            memberCount: memberCount,
            description: description,
            isPrivate: isPrivate,
            type: RoomType(rawValue: type ?? "Regular Room") ?? .regular,
            messageLifetime: messageLifetime,
            avatarStorageId: avatarStorageId,
            avatarURL: nil,
            hasPassword: hasPassword ?? false
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
    let reactions: [ConvexReactionDoc]?
    let expiresAt: Double?  // Unix ms timestamp — set for Chamber of Secrets messages

    func toChatMessage() -> ChatMessage {
        let isSystem = type == "system"
        return ChatMessage(
            id: _id,
            senderId: isSystem ? ChatMessage.systemSenderId : userId,
            senderName: isSystem ? ChatMessage.systemSenderName : (senderName ?? name ?? username ?? "Unknown"),
            content: content,
            type: MessageType(rawValue: type ?? "text") ?? .text,
            timestamp: Date(timeIntervalSince1970: createdAt / 1000),
            roomId: roomId,
            mediaStorageId: mediaStorageId,
            assetURL: nil,
            status: .sent,
            reactions: (reactions ?? []).map { $0.toMessageReaction() },
            expiresAt: expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
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
    let friendshipStatus: String?
    let requestId: String?

    func toChatUser() -> ChatUser {
        ChatUser(
            id: _id,
            name: name,
            username: username,
            email: email ?? "",
            avatarStorageId: avatarStorageId,
            bio: bio,
            deviceTokens: deviceTokens,
            friendshipStatus: FriendshipStatus(rawValue: friendshipStatus ?? "none") ?? .none,
            requestId: requestId
        )
    }
}

struct ConvexFriendRequestDoc: Decodable {
    let _id: String
    let createdAt: Double
    let roomType: String
    let messageLifetime: Double?
    let initialMessage: String
    let user: ConvexUserDoc

    func toFriendRequest() -> FriendRequest {
        FriendRequest(
            id: _id,
            user: user.toChatUser(),
            roomType: RoomType(rawValue: roomType) ?? .regular,
            messageLifetime: messageLifetime,
            initialMessage: initialMessage,
            createdAt: Date(timeIntervalSince1970: createdAt / 1000)
        )
    }
}

struct ConvexFriendRequestMessageDoc: Decodable {
    let _id: String
    let userId: String
    let content: String
    let createdAt: Double

    func toMessage() -> FriendRequestMessage {
        FriendRequestMessage(
            id: _id,
            userId: userId,
            content: content,
            createdAt: Date(timeIntervalSince1970: createdAt / 1000)
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
        // Only include optional fields when non-nil — Convex rejects explicit null for v.optional(...)
        var args: [String: ConvexEncodable?] = [
            "name": name,
            "userId": userId,
            "isPrivate": isPrivate,
            "type": type.rawValue,
        ]
        if let description, !description.isEmpty { args["description"] = description }
        if let messageLifetime { args["messageLifetime"] = messageLifetime }
        if let passwordHash, !passwordHash.isEmpty { args["passwordHash"] = passwordHash }
        let roomId: String = try await convex.mutation("rooms:create", with: args)
        return roomId
    }

    func joinRoom(roomId: String, userId: String, passwordHash: String? = nil) async throws {
        var args: [String: ConvexEncodable?] = [
            "roomId": roomId,
            "userId": userId,
        ]
        if let passwordHash, !passwordHash.isEmpty { args["passwordHash"] = passwordHash }
        try await convex.mutationVoid("rooms:join", with: args)
    }

    func leaveRoom(roomId: String, userId: String) async throws {
        try await convex.mutationVoid("rooms:leave", with: ["roomId": roomId, "userId": userId])
    }

    func deleteRoom(roomId: String, userId: String) async throws {
        try await convex.mutationVoid("rooms:deleteRoom", with: ["roomId": roomId, "userId": userId])
    }

    func updateRoom(roomId: String, userId: String, name: String, description: String?, isPrivate: Bool? = nil, messageLifetime: TimeInterval? = nil) async throws {
        // Only include optional fields when non-nil — Convex rejects explicit null for v.optional(...)
        var args: [String: ConvexEncodable?] = [
            "roomId": roomId,
            "userId": userId,
            "name": name,
        ]
        if let description     { args["description"] = description }
        if let isPrivate       { args["isPrivate"] = isPrivate }
        if let messageLifetime { args["messageLifetime"] = messageLifetime }
        try await convex.mutationVoid("rooms:updateRoom", with: args)
    }

    func fetchRoomMembers(roomId: String) async throws -> [ChatUser] {
        let docs: [ConvexUserDoc] = try await convex.queryOnce("rooms:getMembers", with: ["roomId": roomId])
        return docs.map { $0.toChatUser() }
    }

    func getOrCreateDM(
        userId: String,
        friendId: String,
        roomType: RoomType = .regular,
        messageLifetime: TimeInterval? = nil
    ) async throws -> String {
        var args: [String: ConvexEncodable?] = [
            "userId": userId,
            "friendId": friendId,
            "roomType": roomType.rawValue,
        ]
        if let messageLifetime {
            args["messageLifetime"] = messageLifetime
        }
        let roomId: String = try await convex.mutation("rooms:getOrCreateDM", with: args)
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
            "storageId": storageId
        ])
    }

    func updateRoomAvatar(roomId: String, userId: String, storageId: String) async throws {
        try await convex.mutationVoid("rooms:updateRoomAvatar", with: [
            "roomId": roomId,
            "userId": userId,
            "storageId": storageId
        ])
    }

    func searchUsers(query: String, currentUserId: String) async throws -> [ChatUser] {
        let docs: [ConvexUserDoc] = try await convex.queryOnce("users:searchUsers", with: [
            "query": query,
            "currentUserId": currentUserId
        ])
        return docs.map { $0.toChatUser() }
    }

    func fetchFriends(userId: String) async throws -> [ChatUser] {
        let docs: [ConvexUserDoc] = try await convex.queryOnce("friends:listFriends", with: [
            "userId": userId
        ])
        return docs.map { $0.toChatUser() }
    }

    func fetchIncomingDirectRequests(userId: String) async throws -> [FriendRequest] {
        let docs: [ConvexFriendRequestDoc] = try await convex.queryOnce(
            "friends:listIncomingDirectRequests",
            with: ["userId": userId]
        )
        return docs.map { $0.toFriendRequest() }
    }

    func fetchOutgoingDirectRequests(userId: String) async throws -> [FriendRequest] {
        let docs: [ConvexFriendRequestDoc] = try await convex.queryOnce(
            "friends:listOutgoingDirectRequests",
            with: ["userId": userId]
        )
        return docs.map { $0.toFriendRequest() }
    }

    func createDirectRequest(
        userId: String,
        friendId: String,
        roomType: RoomType,
        messageLifetime: TimeInterval?,
        initialMessage: String
    ) async throws -> String {
        var args: [String: ConvexEncodable?] = [
            "userId": userId,
            "friendId": friendId,
            "roomType": roomType.rawValue,
            "initialMessage": initialMessage,
        ]
        if let messageLifetime {
            args["messageLifetime"] = messageLifetime
        }
        let requestId: String = try await convex.mutation("friends:createDirectRequest", with: args)
        return requestId
    }

    func approveDirectRequest(userId: String, requesterId: String) async throws -> String {
        let roomId: String = try await convex.mutation("friends:approveDirectRequest", with: [
            "userId": userId,
            "requesterId": requesterId,
        ])
        return roomId
    }

    func removeFriend(userId: String, friendId: String) async throws {
        try await convex.mutationVoid("friends:removeFriend", with: [
            "userId": userId,
            "friendId": friendId,
        ])
    }

    func rejectDirectRequest(userId: String, requesterId: String) async throws {
        try await convex.mutationVoid("friends:rejectDirectRequest", with: [
            "userId": userId,
            "requesterId": requesterId,
        ])
    }

    func appendDirectRequestMessage(requestId: String, userId: String, content: String) async throws {
        try await convex.mutationVoid("friends:appendDirectRequestMessage", with: [
            "requestId": requestId,
            "userId": userId,
            "content": content,
        ])
    }

    func fetchDirectRequestMessages(requestId: String) async throws -> [FriendRequestMessage] {
        let docs: [ConvexFriendRequestMessageDoc] = try await convex.queryOnce(
            "friends:listDirectRequestMessages",
            with: ["requestId": requestId]
        )
        return docs.map { $0.toMessage() }
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

    /// Upload a file from disk to Convex storage without loading it fully into memory.
    /// Preferred for video and audio. Returns the storageId.
    func uploadFileFromURL(_ fileURL: URL, mimeType: String) async throws -> String {
        let uploadURL = try await generateUploadURL()
        AppLogger.shared.info("⬆️ uploadFile(url): \(fileURL.lastPathComponent) mime=\(mimeType)")

        guard let url = URL(string: uploadURL) else {
            throw ConvexError.serverError("Invalid upload URL: \(uploadURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let responseBody = String(data: responseData, encoding: .utf8) ?? "<binary>"
        AppLogger.shared.info("⬆️ uploadFile(url): status=\(statusCode)")

        guard statusCode == 200 else {
            let message = statusCode >= 500
                ? "Server is temporarily unavailable (HTTP \(statusCode)). Please try again later."
                : "Upload failed (HTTP \(statusCode))."
            throw ConvexError.serverError(message)
        }

        struct UploadResponse: Decodable { let storageId: String }
        do {
            let result = try JSONDecoder().decode(UploadResponse.self, from: responseData)
            AppLogger.shared.info("⬆️ uploadFile(url): storageId=\(result.storageId)")
            return result.storageId
        } catch {
            throw ConvexError.serverError("Upload response decode failed: \(responseBody)")
        }
    }

    /// Upload data to Convex file storage. Returns the storageId.
    func uploadFile(data: Data, mimeType: String) async throws -> String {
        // 1. Get upload URL
        let uploadURL = try await generateUploadURL()
        AppLogger.shared.info("⬆️ uploadFile: url=\(uploadURL) size=\(data.count)b mime=\(mimeType)")

        guard let url = URL(string: uploadURL) else {
            throw ConvexError.serverError("Invalid upload URL: \(uploadURL)")
        }

        // 2. PUT the file data directly to Convex storage
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let responseBody = String(data: responseData, encoding: .utf8) ?? "<binary>"
        AppLogger.shared.info("⬆️ uploadFile: status=\(statusCode) body=\(responseBody)")

        guard statusCode == 200 else {
            let message = statusCode >= 500
                ? "Server is temporarily unavailable (HTTP \(statusCode)). Please try again later."
                : "Upload failed (HTTP \(statusCode))."
            throw ConvexError.serverError(message)
        }

        // Convex storage responds with {"storageId": "..."}
        struct UploadResponse: Decodable { let storageId: String }
        do {
            let result = try JSONDecoder().decode(UploadResponse.self, from: responseData)
            AppLogger.shared.info("⬆️ uploadFile: storageId=\(result.storageId)")
            return result.storageId
        } catch {
            throw ConvexError.serverError("Upload response decode failed: \(responseBody)")
        }
    }
}
