import Combine
import CryptoKit
import Foundation

/// Manages authentication state using Convex username/password auth.
/// Persists userId in Keychain and username/name in UserDefaults.
@MainActor
final class ConvexAuthService: ObservableObject {
    static let shared = ConvexAuthService()

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var cachedUser: ChatUser?

    private let client = ConvexService.shared.client
    private let keychainUserIdKey = "convex_userId"

    private init() {
        // Restore session from Keychain on launch
        if let storedId = KeychainService.get(keychainUserIdKey) {
            userDefaults.set(storedId, forKey: userIdUserDefaultsKey)
            isAuthenticated = true
            // Load cached user profile in background
            Task { await loadCachedUserProfile(userId: storedId) }
        }
    }

    // MARK: - Auth Operations

    struct AuthResponse: Decodable {
        let userId: String
        let username: String
        let name: String
    }

    func signUp(username: String, password: String, name: String, email: String?) async throws {
        let hash = sha256(password)
        let response: AuthResponse = try await client.mutation("auth:signup", with: [
            "username": username,
            "name": name,
            "passwordHash": hash,
            "email": email
        ])
        await finishSession(response: response)
    }

    func signIn(username: String, password: String) async throws {
        let hash = sha256(password)
        let response: AuthResponse = try await client.mutation("auth:login", with: [
            "username": username,
            "passwordHash": hash
        ])
        await finishSession(response: response)
    }

    func signOut() {
        guard let userId = currentUserId else { return }
        Task {
            try? await client.mutation("auth:logout", with: ["userId": userId])
        }
        KeychainService.delete(keychainUserIdKey)
        userDefaults.removeObject(forKey: userIdUserDefaultsKey)
        userDefaults.removeObject(forKey: "userName")
        isAuthenticated = false
        cachedUser = nil
    }

    func registerDeviceToken(_ token: String) {
        guard let userId = currentUserId else { return }
        Task {
            try? await client.mutation("users:registerDeviceToken", with: [
                "userId": userId,
                "token": token
            ])
        }
    }

    // MARK: - Helpers

    var currentUserId: String? {
        KeychainService.get(keychainUserIdKey)
    }

    private func finishSession(response: AuthResponse) async {
        KeychainService.save(response.userId, for: keychainUserIdKey)
        userDefaults.set(response.userId, forKey: userIdUserDefaultsKey)
        userDefaults.set(response.name, forKey: "userName")
        isAuthenticated = true
        await loadCachedUserProfile(userId: response.userId)

        // Sync device token if one exists
        if let token = userDefaults.string(forKey: "deviceToken") {
            registerDeviceToken(token)
        }
    }

    private func loadCachedUserProfile(userId: String) async {
        struct UserProfileResponse: Decodable {
            let _id: String
            let username: String
            let name: String?
            let email: String?
            let bio: String?
            let avatarStorageId: String?
            let status: String?
        }
        do {
            let profile: UserProfileResponse? = try await ConvexService.shared
                .queryOnce("users:getProfile", with: ["userId": userId])
            if let p = profile {
                cachedUser = ChatUser(
                    id: p._id,
                    name: p.name,
                    username: p.username,
                    email: p.email ?? "",
                    avatarStorageId: p.avatarStorageId,
                    bio: p.bio,
                    deviceTokens: nil
                )
            }
        } catch {
            // Not fatal — profile will load on next opportunity
        }
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
