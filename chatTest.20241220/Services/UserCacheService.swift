import Foundation

/// Service to cache and fetch user information
@MainActor
class UserCacheService {
    static let shared = UserCacheService()
    
    private var userCache: [String: String] = [:] // userId -> userName
    private let cloudKit = CloudKitManager.shared
    private let userIdKey = "userId"
    private var isInitialized = false
    
    private init() {}
    
    /// Initialize cache with current user info
    private func initializeIfNeeded() async {
        guard !isInitialized else { return }
        isInitialized = true
        
        print("🔧 UserCacheService: Initializing...")
        
        // Fetch current user and add to cache
        if let currentUserId = UserDefaults.standard.string(forKey: userIdKey) {
            do {
                let currentUser = try await cloudKit.fetchCurrentUser()
                userCache[currentUserId] = currentUser.name
                print("✅ UserCacheService: Cached current user - \(currentUserId): \(currentUser.name)")
            } catch {
                print("❌ UserCacheService: Failed to fetch current user: \(error)")
            }
        }
    }
    
    /// Get username for a userId, using cache or fetching if needed
    /// - Parameter userId: The user ID to look up
    /// - Returns: The username, or "Unknown User" if not found
    func getUserName(for userId: String) async -> String {
        await initializeIfNeeded()
        
        print("🔍 UserCacheService: Looking up user \(userId)")
        
        // Check cache
        if let cachedName = userCache[userId] {
            print("✅ UserCacheService: Found in cache - \(userId): \(cachedName)")
            return cachedName
        }
        
        print("⚠️ UserCacheService: Not in cache, fetching...")
        
        // Check if it's the current user
        if let currentUserId = UserDefaults.standard.string(forKey: userIdKey),
           userId == currentUserId {
            do {
                let currentUser = try await cloudKit.fetchCurrentUser()
                userCache[userId] = currentUser.name
                print("✅ UserCacheService: Fetched current user - \(userId): \(currentUser.name)")
                return currentUser.name
            } catch {
                print("❌ UserCacheService: Failed to fetch current user: \(error)")
            }
        }
        
        // Fetch from CloudKit (all other users)
        do {
            let users = try await cloudKit.fetchUsers()
            print("📥 UserCacheService: Fetched \(users.count) users from CloudKit")
            
            // Update cache with all fetched users
            for user in users {
                userCache[user.id] = user.name
                print("  - Cached: \(user.id): \(user.name)")
            }
            
            // Return the requested username
            if let name = userCache[userId] {
                print("✅ UserCacheService: Found user - \(userId): \(name)")
                return name
            } else {
                print("⚠️ UserCacheService: User \(userId) not found in fetched results")
                return "Unknown User"
            }
        } catch {
            print("❌ UserCacheService: Failed to fetch users: \(error)")
            return "Unknown User"
        }
    }
    
    /// Get multiple usernames at once
    /// - Parameter userIds: Array of user IDs
    /// - Returns: Dictionary mapping userId to userName
    func getUserNames(for userIds: [String]) async -> [String: String] {
        await initializeIfNeeded()
        
        print("🔍 UserCacheService: Looking up \(userIds.count) users")
        print("  User IDs: \(userIds)")
        
        var result: [String: String] = [:]
        
        // Check which users are not in cache
        let uncachedIds = userIds.filter { userCache[$0] == nil }
        
        if !uncachedIds.isEmpty {
            print("⚠️ UserCacheService: \(uncachedIds.count) users not in cache, fetching...")
            
            // Check if current user is in uncached list
            if let currentUserId = UserDefaults.standard.string(forKey: userIdKey),
               uncachedIds.contains(currentUserId) {
                print("  - Current user needs fetching: \(currentUserId)")
                do {
                    let currentUser = try await cloudKit.fetchCurrentUser()
                    userCache[currentUserId] = currentUser.name
                    print("✅ UserCacheService: Cached current user - \(currentUserId): \(currentUser.name)")
                } catch {
                    print("❌ UserCacheService: Failed to fetch current user: \(error)")
                }
            }
            
            // Fetch all other users to update cache
            do {
                let users = try await cloudKit.fetchUsers()
                print("📥 UserCacheService: Fetched \(users.count) other users from CloudKit")
                for user in users {
                    userCache[user.id] = user.name
                    print("  - Cached: \(user.id): \(user.name)")
                }
            } catch {
                print("❌ UserCacheService: Failed to fetch users: \(error)")
            }
        } else {
            print("✅ UserCacheService: All users found in cache")
        }
        
        // Build result from cache
        for userId in userIds {
            let userName = userCache[userId] ?? "Unknown User"
            result[userId] = userName
            print("  Result: \(userId) → \(userName)")
        }
        
        print("✅ UserCacheService: Returning \(result.count) user names")
        return result
    }
    
    /// Clear the cache (useful after logout or when user data changes)
    func clearCache() {
        print("🧹 UserCacheService: Clearing cache")
        userCache.removeAll()
        isInitialized = false
    }
}