import Foundation

/// Caches user display names to avoid repeated network fetches.
@MainActor
class UserCacheService {
    static let shared = UserCacheService()

    private var userCache: [String: String] = [:]
    private let convexAPI = ConvexChatAPI.shared
    private let userIdKey = "userId"

    private init() {}

    /// Get display name for a userId, using cache or fetching if needed.
    func getUserName(for userId: String) async -> String {
        if let cached = userCache[userId] { return cached }

        do {
            if let user = try await convexAPI.fetchUser(userId: userId) {
                userCache[userId] = user.displayName
                return user.displayName
            }
        } catch {
            print("❌ UserCacheService: Failed to fetch user \(userId): \(error)")
        }
        return "Unknown User"
    }

    /// Get multiple usernames at once.
    func getUserNames(for userIds: [String]) async -> [String: String] {
        var result: [String: String] = [:]
        for userId in userIds {
            result[userId] = await getUserName(for: userId)
        }
        return result
    }

    /// Clear the cache on logout or when user data changes.
    func clearCache() {
        userCache.removeAll()
    }
}
