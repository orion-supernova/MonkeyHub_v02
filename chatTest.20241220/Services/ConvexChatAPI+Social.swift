import Foundation
import ConvexMobile

// MARK: - Shared-context document (rooms:listShared)

/// Rooms two users share + whether they have a DM. Used by the block-confirm UI.
struct SharedContext: Decodable {
    struct SharedRoom: Decodable {
        let _id: String
        let name: String
        let memberCount: Int
        let avatarStorageId: String?
        let isPrivate: Bool
        let type: String?
    }
    let groupRooms: [SharedRoom]
    let hasDm: Bool
}

/// Read-state row (messages:getReadState): a member and how far they've read.
private struct ConvexReadStateDoc: Decodable {
    let userId: String
    let lastReadAt: Double
}

// MARK: - Social, privacy, replies, read receipts

extension ConvexChatAPI {

    // MARK: Blocking

    func blockUser(userId: String, targetUserId: String, deleteDm: Bool = false) async throws {
        var args: [String: ConvexEncodable?] = [
            "userId": userId,
            "targetUserId": targetUserId,
        ]
        if deleteDm { args["deleteDm"] = true }
        try await ConvexService.shared.mutationVoid("users:blockUser", with: args)
    }

    func unblockUser(userId: String, targetUserId: String) async throws {
        try await ConvexService.shared.mutationVoid("users:unblockUser", with: [
            "userId": userId,
            "targetUserId": targetUserId,
        ])
    }

    func listBlocked(userId: String) async throws -> [BlockedUser] {
        struct Doc: Decodable {
            let _id: String
            let username: String
            let name: String
            let avatarStorageId: String?
        }
        let docs: [Doc] = try await ConvexService.shared.queryOnce("users:listBlocked", with: ["userId": userId])
        return docs.map { BlockedUser(id: $0._id, username: $0.username, name: $0.name, avatarStorageId: $0.avatarStorageId) }
    }

    func isBlocked(userId: String, otherUserId: String) async throws -> Bool {
        try await ConvexService.shared.queryOnce("users:isBlocked", with: [
            "userId": userId,
            "otherUserId": otherUserId,
        ])
    }

    func listShared(userId: String, otherUserId: String) async throws -> SharedContext {
        try await ConvexService.shared.queryOnce("rooms:listShared", with: [
            "userId": userId,
            "otherUserId": otherUserId,
        ])
    }

    // MARK: Reporting

    func report(reporterId: String, targetType: String, targetId: String, reason: String, note: String? = nil) async throws {
        var args: [String: ConvexEncodable?] = [
            "reporterId": reporterId,
            "targetType": targetType,
            "targetId": targetId,
            "reason": reason,
        ]
        if let note, !note.isEmpty { args["note"] = note }
        try await ConvexService.shared.mutationVoid("users:report", with: args)
    }

    // MARK: Self profile (with visibility)

    /// Fetches the caller's own profile, passing `viewerUserId == userId` so the
    /// backend includes the self-only `visibility` map (omitted for other viewers).
    func fetchOwnProfile(userId: String) async throws -> ChatUser? {
        let doc: ConvexUserDoc? = try await ConvexService.shared.queryOnce(
            "users:getProfile",
            with: ["userId": userId, "viewerUserId": userId]
        )
        return doc?.toChatUser()
    }

    /// Fetches another user's profile as seen by `viewerUserId` (privacy-redacted).
    func fetchProfile(userId: String, viewerUserId: String) async throws -> ChatUser? {
        let doc: ConvexUserDoc? = try await ConvexService.shared.queryOnce(
            "users:getProfile",
            with: ["userId": userId, "viewerUserId": viewerUserId]
        )
        return doc?.toChatUser()
    }

    // MARK: Profile visibility

    /// Update one or more visibility fields. Omitted fields are left unchanged.
    func updateVisibility(
        userId: String,
        avatar: VisibilityLevel? = nil,
        status: VisibilityLevel? = nil,
        lastSeen: VisibilityLevel? = nil,
        seen: VisibilityLevel? = nil,
        acceptsFriendRequests: Bool? = nil
    ) async throws {
        var args: [String: ConvexEncodable?] = ["userId": userId]
        if let avatar { args["avatar"] = avatar.rawValue }
        if let status { args["status"] = status.rawValue }
        if let lastSeen { args["lastSeen"] = lastSeen.rawValue }
        if let seen { args["seen"] = seen.rawValue }
        if let acceptsFriendRequests { args["friendRequests"] = acceptsFriendRequests ? "public" : "nobody" }
        try await ConvexService.shared.mutationVoid("users:updateVisibility", with: args)
    }

    // MARK: Presence

    func updateStatus(userId: String, status: String) async throws {
        try await ConvexService.shared.mutationVoid("users:updateStatus", with: [
            "userId": userId,
            "status": status,
        ])
    }

    // MARK: Read receipts

    func markRoomRead(roomId: String, userId: String) async throws {
        try await ConvexService.shared.mutationVoid("messages:markRoomRead", with: [
            "roomId": roomId,
            "userId": userId,
        ])
    }

    /// Returns each member's last-read timestamp (privacy-filtered by the backend).
    func fetchReadState(roomId: String, viewerUserId: String) async throws -> [String: Date] {
        let docs: [ConvexReadStateDoc] = try await ConvexService.shared.queryOnce(
            "messages:getReadState",
            with: ["roomId": roomId, "viewerUserId": viewerUserId]
        )
        var out: [String: Date] = [:]
        for d in docs { out[d.userId] = Date(timeIntervalSince1970: d.lastReadAt / 1000) }
        return out
    }

    // MARK: Threads

    /// Returns the full reply chain around a message, in chronological order.
    func fetchThread(messageId: String, maxTotal: Int = 50) async throws -> [ChatMessage] {
        let docs: [ConvexMessageDoc] = try await ConvexService.shared.queryOnce(
            "messages:getThread",
            with: ["messageId": messageId, "maxTotal": Double(maxTotal)]
        )
        return docs.map { $0.toChatMessage() }
    }
}
