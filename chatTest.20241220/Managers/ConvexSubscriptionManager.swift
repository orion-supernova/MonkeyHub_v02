import Combine
import ConvexMobile
import Foundation

/// Manages Convex real-time subscriptions for rooms, messages, and typing.
/// Replaces NotificationSubscriptionManager + CloudKit push subscriptions.
///
/// With Convex, subscriptions deliver the FULL updated dataset on every change —
/// so there is NO deduplication needed. The subscription IS the single source of truth.
@MainActor
final class ConvexSubscriptionManager: ObservableObject {
    static let shared = ConvexSubscriptionManager()

    private let client = ConvexService.shared.client
    private let repository = ChatRepository.shared

    // Cancellables keyed by subscription name
    private var roomsSubscription: AnyCancellable?
    private var roomListTypingSubscription: AnyCancellable?
    private var messagesSubscription: AnyCancellable?
    private var typingSubscription: AnyCancellable?

    private var activeRoomId: String?
    private var activeUserId: String?

    private init() {}

    // MARK: - Room List Subscription

    /// Subscribe to the user's room list in real-time.
    /// Call this once after login. Stays active for the app's lifetime.
    func subscribeToRooms(userId: String) {
        activeUserId = userId
        roomsSubscription?.cancel()
        roomListTypingSubscription?.cancel()

        roomsSubscription = client
            .subscribe(to: "rooms:listUserRooms", with: ["userId": userId], yielding: [ConvexRoomDoc].self)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] docs in
                    let rooms = docs.map { $0.toChatRoom() }
                    self?.repository.handleRoomsUpdate(rooms)
                }
            )

        roomListTypingSubscription = client
            .subscribe(to: "typing:getTypingForUser", with: ["userId": userId], yielding: [String: [String]].self)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] typingMap in
                    self?.repository.handleRoomListTypingUpdate(typingMap)
                }
            )
    }

    // MARK: - Active Room Subscriptions

    /// Subscribe to messages and typing for a specific room.
    /// Call when the user enters a room; cleans up previous subscriptions automatically.
    func subscribeToRoom(_ roomId: String) {
        guard activeRoomId != roomId else { return }
        unsubscribeFromCurrentRoom()
        activeRoomId = roomId

        // Messages subscription
        messagesSubscription = client
            .subscribe(to: "messages:list", with: ["roomId": roomId, "limit": Double(100)], yielding: [ConvexMessageDoc].self)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        AppLogger.shared.logError("messages:list subscription", error)
                    }
                },
                receiveValue: { [weak self] docs in
                    let messages = docs.map { $0.toChatMessage() }
                    let reactionCount = messages.reduce(0) { $0 + $1.reactions.count }
                    AppLogger.shared.info("💬 messages update: \(messages.count) msgs, \(reactionCount) reactions in \(roomId)")
                    self?.repository.handleMessagesSubscriptionUpdate(messages, for: roomId)
                }
            )

        // Typing subscription
        let currentUserId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        typingSubscription = client
            .subscribe(
                to: "typing:getTypingUsers",
                with: ["roomId": roomId, "currentUserId": currentUserId],
                yielding: [ConvexTypingUser].self
            )
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        AppLogger.shared.logError("typing:getTypingUsers", error)
                    }
                },
                receiveValue: { users in
                    AppLogger.shared.info("⌨️ typing update: \(users.count) user(s) typing in \(roomId)")
                    TypingIndicatorManager.shared.handleConvexUpdate(users, for: roomId)
                }
            )
    }

    func unsubscribeFromCurrentRoom() {
        messagesSubscription?.cancel()
        messagesSubscription = nil
        typingSubscription?.cancel()
        typingSubscription = nil
        activeRoomId = nil
    }

    func clearAll() {
        roomsSubscription?.cancel()
        roomsSubscription = nil
        roomListTypingSubscription?.cancel()
        roomListTypingSubscription = nil
        unsubscribeFromCurrentRoom()
        activeUserId = nil
    }
}
