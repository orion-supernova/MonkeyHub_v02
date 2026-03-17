import Foundation
import Combine

/// Manages typing indicators with Convex integration and automatic cleanup.
/// Real-time updates arrive via ConvexSubscriptionManager.handleConvexUpdate(_:for:).
@MainActor
final class TypingIndicatorManager: ObservableObject {
    static let shared = TypingIndicatorManager()

    // MARK: - Published State
    @Published private(set) var typingUsers: [String: [TypingIndicator]] = [:]

    // MARK: - Dependencies
    private let convexAPI = ConvexChatAPI.shared
    private let userDefaults = UserDefaults.standard
    private let userIdUserDefaultsKey = "userId"
    private let userNameUserDefaultsKey = "userName"

    // MARK: - Internal State
    private var typingTimers: [String: Timer] = [:]
    private var inactivityTimers: [String: Timer] = [:]
    private var lastSentTime: [String: Date] = [:]
    private var cleanupTimers: [String: Timer] = [:]
    private var activeRoomId: String?
    private var isCurrentlyTyping: [String: Bool] = [:]

    // MARK: - Configuration
    private let sendInterval: TimeInterval = 2.0      // heartbeat while typing
    private let throttleInterval: TimeInterval = 0.5
    private let inactivityTimeout: TimeInterval = 0.8  // safety net for mid-sentence pauses

    private init() {}

    // MARK: - Convex Subscription Callback

    /// Called by ConvexSubscriptionManager when the typing subscription delivers an update.
    /// The list contains ONLY other users who are currently typing (Convex excludes self server-side).
    func handleConvexUpdate(_ users: [ConvexTypingUser], for roomId: String) {
        guard roomId == activeRoomId else {
            AppLogger.shared.info("⌨️ handleConvexUpdate: ignored (activeRoomId=\(activeRoomId ?? "nil"), roomId=\(roomId))")
            return
        }

        let currentUserId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""

        // Preserve the local user's own indicator if they're currently typing
        let localIndicator = typingUsers[roomId]?.first { $0.userId == currentUserId }

        let remoteIndicators = users
            .filter { $0.userId != currentUserId }
            .map { $0.toTypingIndicator(roomId: roomId) }

        var final: [TypingIndicator] = []
        if let local = localIndicator { final.append(local) }
        final.append(contentsOf: remoteIndicators)

        typingUsers[roomId] = final

        for indicator in remoteIndicators {
            scheduleCleanup(for: indicator)
        }
    }

    // MARK: - Public API

    func onTextChanged(in roomId: String) {
        guard activeRoomId == roomId else { return }

        // Reset inactivity timer on every keystroke
        inactivityTimers[roomId]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: inactivityTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleInactivity(in: roomId) }
        }
        inactivityTimers[roomId] = timer

        if isCurrentlyTyping[roomId] == true { return }
        startTyping(in: roomId)
    }

    private func startTyping(in roomId: String) {
        guard activeRoomId == roomId, isCurrentlyTyping[roomId] != true else { return }
        isCurrentlyTyping[roomId] = true

        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let userName = userDefaults.string(forKey: userNameUserDefaultsKey) ?? "User"

        // Instant local update
        let localIndicator = TypingIndicator(roomId: roomId, userId: userId, userName: userName)
        var indicators = typingUsers[roomId] ?? []
        indicators.removeAll { $0.userId == userId }
        indicators.append(localIndicator)
        typingUsers[roomId] = indicators

        Task { await sendTypingWithThrottle(for: roomId) }

        typingTimers[roomId]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: sendInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sendTypingToConvex(for: roomId) }
        }
        typingTimers[roomId] = timer
    }

    func stopTyping(in roomId: String) {
        guard isCurrentlyTyping[roomId] == true else { return }
        isCurrentlyTyping[roomId] = false

        typingTimers[roomId]?.invalidate()
        typingTimers[roomId] = nil
        inactivityTimers[roomId]?.invalidate()
        inactivityTimers[roomId] = nil

        let currentUserId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        typingUsers[roomId]?.removeAll { $0.userId == currentUserId }

        Task { await clearTypingFromConvex(for: roomId) }
    }

    /// Clears the active room only if it matches the expected roomId.
    /// Safe to call from deinit Tasks where a new room may already be active.
    func clearIfActive(_ roomId: String) {
        guard activeRoomId == roomId else { return }
        setActiveRoom(nil)
    }

    func setActiveRoom(_ roomId: String?) {
        if let previous = activeRoomId { stopTyping(in: previous) }
        activeRoomId = roomId

        if roomId == nil {
            typingUsers.removeAll()
            cleanupTimers.values.forEach { $0.invalidate() }
            cleanupTimers.removeAll()
            inactivityTimers.values.forEach { $0.invalidate() }
            inactivityTimers.removeAll()
            isCurrentlyTyping.removeAll()
            lastSentTime.removeAll()
        }
    }

    func getTypingText(for roomId: String) -> String? {
        let currentUserId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let others = (typingUsers[roomId] ?? []).filter { $0.userId != currentUserId && !$0.isExpired }
        guard !others.isEmpty else { return nil }
        switch others.count {
        case 1:
            return "\(others[0].userName) is typing..."
        case 2:
            return "\(others[0].userName) and \(others[1].userName) are typing..."
        case 3:
            return "\(others[0].userName), \(others[1].userName), and \(others[2].userName) are typing..."
        default:
            return "\(others[0].userName), \(others[1].userName), and \(others.count - 2) others are typing..."
        }
    }

    // MARK: - Convex Operations

    private func sendTypingWithThrottle(for roomId: String) async {
        let now = Date()
        if let last = lastSentTime[roomId], now.timeIntervalSince(last) < throttleInterval { return }
        lastSentTime[roomId] = now
        await sendTypingToConvex(for: roomId)
    }

    private func sendTypingToConvex(for roomId: String) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        guard !userId.isEmpty else { return }
        do { try await convexAPI.setTyping(roomId: roomId, userId: userId) }
        catch { print("❌ TypingIndicator: setTyping failed: \(error)") }
    }

    private func clearTypingFromConvex(for roomId: String) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        guard !userId.isEmpty else { return }
        do { try await convexAPI.clearTyping(roomId: roomId, userId: userId) }
        catch { print("❌ TypingIndicator: clearTyping failed: \(error)") }
    }

    // MARK: - Cleanup

    private func handleInactivity(in roomId: String) {
        stopTyping(in: roomId)
    }

    private func scheduleCleanup(for indicator: TypingIndicator) {
        cleanupTimers[indicator.id]?.invalidate()
        let delay = max(0.1, indicator.expiresAt.timeIntervalSinceNow)
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.removeExpiredIndicator(indicator) }
        }
        cleanupTimers[indicator.id] = timer
    }

    private func removeExpiredIndicator(_ indicator: TypingIndicator) {
        typingUsers[indicator.roomId]?.removeAll { $0.id == indicator.id }
        cleanupTimers[indicator.id]?.invalidate()
        cleanupTimers[indicator.id] = nil
    }
}
