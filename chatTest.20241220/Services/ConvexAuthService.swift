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

    private let convex = ConvexService.shared
    private let keychainUserIdKey = "convex_userId"

    private init() {
        // Restore session from Keychain on launch
        if let storedId = KeychainService.get(keychainUserIdKey) {
            userDefaults.set(storedId, forKey: userIdUserDefaultsKey)
            isAuthenticated = true
            // Load cached user profile in background
            Task { await loadCachedUserProfile(userId: storedId) }
            // Start real-time subscriptions
            ConvexSubscriptionManager.shared.subscribeToRooms(userId: storedId)
            // Start VoIP call session (signaling + presence + push registration)
            CallController.shared.startSession(userId: storedId)
            // Re-associate this device with the logged-in user in OneSignal.
            // Deferred to next run-loop tick so ConvexAuthService.shared is fully
            // initialised before PushNotificationManager accesses currentUserId.
            Task { @MainActor in
                PushNotificationManager.shared.setExternalUserId(storedId)
            }
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
        let response: AuthResponse = try await convex.mutation("auth:signup", with: [
            "username": username,
            "name": name,
            "passwordHash": hash,
            "email": email
        ])
        await finishSession(response: response)
    }

    func signIn(username: String, password: String) async throws {
        let hash = sha256(password)
        let response: AuthResponse = try await convex.mutation("auth:login", with: [
            "username": username,
            "passwordHash": hash
        ])
        await finishSession(response: response)
    }

    func signOut() {
        guard let userId = currentUserId else { return }
        Task {
            try? await convex.mutationVoid("auth:logout", with: ["userId": userId])
        }
        // Stop all subscriptions
        ConvexSubscriptionManager.shared.clearAll()
        CallController.shared.endSession()
        // Disassociate this device from the user in OneSignal before clearing credentials.
        PushNotificationManager.shared.logout()
        KeychainService.delete(keychainUserIdKey)
        userDefaults.removeObject(forKey: userIdUserDefaultsKey)
        userDefaults.removeObject(forKey: "userName")
        isAuthenticated = false
        cachedUser = nil
    }

    /// Permanently deletes the account (cascade on the backend), then signs out.
    func deleteAccount() async {
        guard let userId = currentUserId else { return }
        do {
            try await convex.mutationVoid("auth:deleteAccount", with: ["userId": userId])
        } catch {
            AppLogger.shared.logError("auth:deleteAccount", error)
        }
        signOut()
    }

    // MARK: - Helpers

    var currentUserId: String? {
        KeychainService.get(keychainUserIdKey)
    }

    /// Reads the stored user ID directly from Keychain without accessing the
    /// shared singleton or triggering any initialization side-effects.
    /// Safe to call from AppDelegate before SwiftUI starts.
    nonisolated static var storedUserId: String? {
        KeychainService.get("convex_userId")
    }

    private func finishSession(response: AuthResponse) async {
        KeychainService.save(response.userId, for: keychainUserIdKey)
        userDefaults.set(response.userId, forKey: userIdUserDefaultsKey)
        userDefaults.set(response.name, forKey: "userName")
        isAuthenticated = true
        await loadCachedUserProfile(userId: response.userId)

        // Start real-time subscriptions
        ConvexSubscriptionManager.shared.subscribeToRooms(userId: response.userId)
        // Start VoIP call session (signaling + presence + push registration)
        CallController.shared.startSession(userId: response.userId)

        // Associate this device with the newly authenticated user in OneSignal.
        // OneSignal.initialize was already called at app launch — this just links the user.
        PushNotificationManager.shared.setExternalUserId(response.userId)
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
                // Keep UserDefaults in sync so ChatRoomViewModel always has the correct name.
                userDefaults.set(p.name ?? p.username, forKey: "userName")
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
