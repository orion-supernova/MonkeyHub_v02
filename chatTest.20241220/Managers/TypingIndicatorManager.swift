import Foundation
import CloudKit
import Combine

/// Manages typing indicators with CloudKit integration and automatic cleanup
@MainActor
final class TypingIndicatorManager: ObservableObject {
    static let shared = TypingIndicatorManager()
    
    // MARK: - Published State
    @Published private(set) var typingUsers: [String: [TypingIndicator]] = [:] // roomId -> [indicators]
    
    // MARK: - Dependencies
    private let cloudKit = CloudKitManager.shared
    private let userDefaults = UserDefaults.standard
    private let userIdUserDefaultsKey = "userId"
    
    // MARK: - Internal State
    private var typingTimers: [String: Timer] = [:] // roomId -> timer for sending
    private var inactivityTimers: [String: Timer] = [:] // roomId -> timer for detecting inactivity
    private var lastSentTime: [String: Date] = [:] // roomId -> last time we sent to CloudKit
    private var cleanupTimers: [String: Timer] = [:] // indicatorId -> cleanup timer
    private var activeRoomId: String?
    private var cachedUserName: String?
    private var isCurrentlyTyping: [String: Bool] = [:] // roomId -> typing state
    
    // MARK: - Deduplication (Single Source of Truth)
    // The Manager is the ONLY place that deduplicates typing indicators
    private var processedIndicatorIds = Set<String>() // Track processed typing indicator IDs
    private let maxProcessedIdsCache = 500 // Prevent memory bloat
    
    // MARK: - Configuration
    private let sendInterval: TimeInterval = 1.0 // Send to CloudKit every 1 second
    private let throttleInterval: TimeInterval = 0.5 // Minimum time between CloudKit sends
    private let inactivityTimeout: TimeInterval = 3.0 // Stop typing after 3 seconds of no keyboard activity
    
    private init() {
        // Cache user name at init for instant local updates
        Task {
            if let user = try? await cloudKit.fetchCurrentUser() {
                self.cachedUserName = user.name
            }
        }
    }
    
    // MARK: - Public API
    
    /// Called on every text change - handles state management
    func onTextChanged(in roomId: String) {
        guard activeRoomId == roomId else { return }
        
        // Reset inactivity timer on every keystroke
        inactivityTimers[roomId]?.invalidate()
        let inactivityTimer = Timer.scheduledTimer(withTimeInterval: inactivityTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleInactivity(in: roomId)
            }
        }
        inactivityTimers[roomId] = inactivityTimer
        
        // If already typing, just reset the timer
        if isCurrentlyTyping[roomId] == true {
            print("⌨️ TypingIndicator: Still typing (inactivity timer reset)")
            return
        }
        
        // Start typing immediately (no debounce for local UI)
        startTyping(in: roomId)
    }
    
    /// Start tracking typing for a room
    private func startTyping(in roomId: String) {
        guard activeRoomId == roomId else { return }
        guard isCurrentlyTyping[roomId] != true else { return } // Already typing
        
        isCurrentlyTyping[roomId] = true
        
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let userName = cachedUserName ?? "User"
        
        // INSTANT LOCAL UPDATE - Add to local state immediately
        let localIndicator = TypingIndicator(
            roomId: roomId,
            userId: userId,
            userName: userName
        )
        
        // Add to local state instantly (for your own typing)
        var indicators = typingUsers[roomId] ?? []
        indicators.removeAll { $0.userId == userId } // Remove old one if exists
        indicators.append(localIndicator)
        typingUsers[roomId] = indicators
        
        print("⚡️ TypingIndicator: Started typing (instant local update)")
        
        // Send to CloudKit with throttling
        Task {
            await sendTypingIndicatorWithThrottle(for: roomId)
        }
        
        // Schedule repeating sends to CloudKit every 1 second
        typingTimers[roomId]?.invalidate() // Clean up any existing timer
        let timer = Timer.scheduledTimer(withTimeInterval: sendInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sendTypingIndicatorToCloudKit(for: roomId)
            }
        }
        typingTimers[roomId] = timer
    }
    
    /// Stop tracking typing for a room
    func stopTyping(in roomId: String) {
        guard isCurrentlyTyping[roomId] == true else { return } // Not typing
        
        isCurrentlyTyping[roomId] = false
        
        typingTimers[roomId]?.invalidate()
        typingTimers[roomId] = nil
        
        inactivityTimers[roomId]?.invalidate()
        inactivityTimers[roomId] = nil
        
        let currentUserId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        
        // INSTANT LOCAL REMOVAL
        typingUsers[roomId]?.removeAll { $0.userId == currentUserId }
        
        print("⚡️ TypingIndicator: Stopped typing (instant local removal)")
        
        // Remove indicator from CloudKit (background, don't wait)
        Task {
            await removeTypingIndicator(for: roomId)
        }
    }
    
    /// Handle user inactivity (stopped typing but didn't clear text)
    private func handleInactivity(in roomId: String) {
        print("⏸️ TypingIndicator: User inactive for \(inactivityTimeout)s, auto-stopping")
        stopTyping(in: roomId)
    }
    
    /// Set the active room for receiving typing indicators
    func setActiveRoom(_ roomId: String?) {
        // Stop typing in previous room
        if let previousRoom = activeRoomId {
            stopTyping(in: previousRoom)
        }
        
        self.activeRoomId = roomId
        
        if let roomId = roomId {
            // Subscribe to typing indicators for this room (like messages do)
            Task {
                await subscribeToTypingIndicators(in: roomId)
                // Initial fetch to get current state
                await fetchTypingIndicators(for: roomId)
            }
        } else {
            // Clear typing state when leaving room
            typingUsers.removeAll()
            cleanupTimers.values.forEach { $0.invalidate() }
            cleanupTimers.removeAll()
            inactivityTimers.values.forEach { $0.invalidate() }
            inactivityTimers.removeAll()
            isCurrentlyTyping.removeAll()
            lastSentTime.removeAll()
        }
    }
    
    /// Get formatted typing text for a room
    func getTypingText(for roomId: String) -> String? {
        guard let indicators = typingUsers[roomId], !indicators.isEmpty else {
            return nil
        }
        
        let currentUserId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let otherUsers = indicators.filter { $0.userId != currentUserId && !$0.isExpired }
        
        guard !otherUsers.isEmpty else { return nil }
        
        switch otherUsers.count {
        case 1:
            return "\(otherUsers[0].userName) is typing..."
        case 2:
            return "\(otherUsers[0].userName) and \(otherUsers[1].userName) are typing..."
        case 3:
            return "\(otherUsers[0].userName), \(otherUsers[1].userName), and \(otherUsers[2].userName) are typing..."
        default:
            return "\(otherUsers[0].userName), \(otherUsers[1].userName), and \(otherUsers.count - 2) others are typing..."
        }
    }
    
    // MARK: - CloudKit Operations
    
    /// Send typing indicator with throttling (prevents sending too frequently)
    private func sendTypingIndicatorWithThrottle(for roomId: String) async {
        let now = Date()
        
        // Check if we sent recently (within throttle interval)
        if let lastSent = lastSentTime[roomId] {
            let timeSinceLastSend = now.timeIntervalSince(lastSent)
            if timeSinceLastSend < throttleInterval {
                print("🚫 TypingIndicator: Throttled (last sent \(String(format: "%.2f", timeSinceLastSend))s ago)")
                return
            }
        }
        
        // Update last sent time
        lastSentTime[roomId] = now
        
        // Actually send to CloudKit
        await sendTypingIndicatorToCloudKit(for: roomId)
    }
    
    private func sendTypingIndicatorToCloudKit(for roomId: String) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let userName = cachedUserName ?? "User"
        
        let indicator = TypingIndicator(
            roomId: roomId,
            userId: userId,
            userName: userName
        )
        
        let record = indicator.toRecord()
        
        do {
            _ = try await cloudKit.database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .changedKeys
            )
            print("✅ TypingIndicator: Synced to CloudKit for room \(roomId)")
        } catch {
            print("❌ TypingIndicator: CloudKit sync failed: \(error)")
        }
    }
    
    private func removeTypingIndicator(for roomId: String) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let indicatorId = "\(roomId)_\(userId)"
        let recordID = CKRecord.ID(recordName: indicatorId)
        
        do {
            try await cloudKit.database.deleteRecord(withID: recordID)
            print("✅ TypingIndicator: Removed from CloudKit")
        } catch let error as CKError where error.code == .unknownItem {
            print("ℹ️ TypingIndicator: Already removed from CloudKit")
        } catch {
            print("❌ TypingIndicator: CloudKit delete failed: \(error)")
        }
    }
    
    private func fetchTypingIndicators(for roomId: String) async {
        let predicate = NSPredicate(
            format: "%K == %@",
            TypingIndicator.roomIdKey,
            roomId
        )
        let query = CKQuery(recordType: TypingIndicator.recordType, predicate: predicate)
        
        do {
            let (records, _) = try await cloudKit.database.records(matching: query)
            let indicators = try records.compactMap { result -> TypingIndicator? in
                let record = try result.1.get()
                return try TypingIndicator(from: record)
            }
            
            updateTypingIndicatorsFromCloudKit(indicators, for: roomId)
            print("✅ TypingIndicator: Fetched \(indicators.count) indicators for room \(roomId)")
        } catch {
            print("❌ TypingIndicator: Fetch failed: \(error)")
        }
    }
    
    private func subscribeToTypingIndicators(in roomId: String) async {
        let predicate = NSPredicate(
            format: "%K == %@",
            TypingIndicator.roomIdKey,
            roomId
        )
        
        let subscription = CKQuerySubscription(
            recordType: TypingIndicator.recordType,
            predicate: predicate,
            subscriptionID: "typing-\(roomId)",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        // Silent subscription for data refresh only
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.shouldBadge = false
        notificationInfo.alertBody = "" // Silent
        notificationInfo.desiredKeys = [
            TypingIndicator.userIdKey,
            TypingIndicator.userNameKey,
            TypingIndicator.roomIdKey,
            TypingIndicator.timestampKey
        ]
        
        subscription.notificationInfo = notificationInfo
        
        do {
            _ = try await cloudKit.database.modifySubscriptions(
                saving: [subscription],
                deleting: []
            )
            print("✅ TypingIndicator: Subscribed to room \(roomId)")
        } catch let error as CKError {
            print("ℹ️ TypingIndicator: Subscription info: \(error.localizedDescription)")
        } catch {
            print("❌ TypingIndicator: Subscription failed: \(error)")
        }
    }
    
    // MARK: - State Management
    
    /// Update typing indicators from CloudKit (EXACT SAME PATTERN AS MESSAGES)
    private func updateTypingIndicatorsFromCloudKit(_ indicators: [TypingIndicator], for roomId: String) {
        guard roomId == activeRoomId else { return }
        
        let currentUserId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        
        // Get current local state
        var currentIndicators = typingUsers[roomId] ?? []
        
        // Keep local user's indicator if they're typing (it's authoritative - like pending messages)
        let localUserIndicator = currentIndicators.first { $0.userId == currentUserId }
        
        // Filter CloudKit indicators (exclude expired and current user)
        let validCloudKitIndicators = indicators.filter {
            !$0.isExpired && $0.userId != currentUserId
        }
        
        // Build final list: local user indicator + other users from CloudKit
        var finalIndicators: [TypingIndicator] = []
        
        // Add local user first (if typing)
        if let localIndicator = localUserIndicator {
            finalIndicators.append(localIndicator)
        }
        
        // Add others from CloudKit
        finalIndicators.append(contentsOf: validCloudKitIndicators)
        
        // Remove duplicates by userId
        var seenUserIds = Set<String>()
        finalIndicators = finalIndicators.filter { indicator in
            if seenUserIds.contains(indicator.userId) {
                return false
            }
            seenUserIds.insert(indicator.userId)
            return true
        }
        
        // Update state
        typingUsers[roomId] = finalIndicators
        
        // Schedule cleanup timers for CloudKit indicators only
        for indicator in validCloudKitIndicators {
            scheduleCleanup(for: indicator)
        }
        
        print("🔄 TypingIndicator: Updated state - \(finalIndicators.count) users typing")
    }
    
    private func scheduleCleanup(for indicator: TypingIndicator) {
        // Cancel existing timer
        cleanupTimers[indicator.id]?.invalidate()
        
        // Calculate time until expiration
        let timeUntilExpiration = max(0.1, indicator.expiresAt.timeIntervalSinceNow)
        
        let timer = Timer.scheduledTimer(withTimeInterval: timeUntilExpiration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeExpiredIndicator(indicator)
            }
        }
        
        cleanupTimers[indicator.id] = timer
    }
    
    private func removeExpiredIndicator(_ indicator: TypingIndicator) {
        typingUsers[indicator.roomId]?.removeAll { $0.id == indicator.id }
        cleanupTimers[indicator.id]?.invalidate()
        cleanupTimers[indicator.id] = nil
        
        print("🧹 TypingIndicator: Cleaned up expired indicator for \(indicator.userName)")
    }
    
    // MARK: - Notification Handling (USE NOTIFICATION PAYLOAD LIKE MESSAGES)
    
    /// Handle incoming typing indicator notification - use payload data directly
    /// This is the SINGLE SOURCE OF TRUTH for typing indicator deduplication.
    func handleTypingNotification(_ userInfo: [AnyHashable: Any]) {
        guard let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
              let recordID = cloudKitNotification.recordID,
              let recordFields = cloudKitNotification.recordFields
        else {
            print("❌ TypingIndicator: Invalid notification format")
            return
        }
        
        // Extract room ID from indicator ID (format: "roomId_userId")
        let indicatorId = recordID.recordName
        guard let roomId = indicatorId.components(separatedBy: "_").first else {
            print("❌ TypingIndicator: Could not parse roomId from indicator ID")
            return
        }
        
        // Only process if we're in this room
        guard roomId == activeRoomId else {
            print("ℹ️ TypingIndicator: Notification for inactive room \(roomId), ignoring")
            return
        }
        
        // DEDUPLICATION: Check if we've already processed this indicator event
        let deduplicationKey = "\(indicatorId)_\(cloudKitNotification.queryNotificationReason.rawValue)"
        if processedIndicatorIds.contains(deduplicationKey) {
            print("♻️ TypingIndicator: Skipping duplicate notification for \(indicatorId)")
            return
        }
        
        // Mark as processed
        processedIndicatorIds.insert(deduplicationKey)
        
        // Cleanup cache if it grows too large
        if processedIndicatorIds.count > maxProcessedIdsCache {
            print("🧹 TypingIndicator: Cleaning processed indicator cache")
            let toRemove = processedIndicatorIds.prefix(maxProcessedIdsCache / 2)
            processedIndicatorIds.subtract(toRemove)
        }

        print("📥 TypingIndicator: Received notification for room \(roomId)")
        
        // Check notification type
        switch cloudKitNotification.queryNotificationReason {
        case .recordCreated, .recordUpdated:
            // Someone is typing - extract data from notification payload
            guard let userId = recordFields[TypingIndicator.userIdKey] as? String,
                  let userName = recordFields[TypingIndicator.userNameKey] as? String else {
                print("❌ TypingIndicator: Missing required fields in notification")
                return
            }
            
            let currentUserId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
            guard userId != currentUserId else {
                print("ℹ️ TypingIndicator: Ignoring own typing notification")
                return
            }
            
            // Create indicator from notification data
            let indicator = TypingIndicator(
                roomId: roomId,
                userId: userId,
                userName: userName
            )
            
            print("✅ TypingIndicator: \(userName) is typing (from notification)")
            
            // Add to state (with secondary deduplication by userId)
            var indicators = typingUsers[roomId] ?? []
            indicators.removeAll { $0.userId == userId } // Remove old one
            indicators.append(indicator)
            typingUsers[roomId] = indicators
            
            // Schedule cleanup
            scheduleCleanup(for: indicator)
            
        case .recordDeleted:
            // Someone stopped typing
            let userId = indicatorId.components(separatedBy: "_").last ?? ""
            typingUsers[roomId]?.removeAll { $0.userId == userId }
            print("✅ TypingIndicator: User \(userId) stopped typing (from notification)")
            
        @unknown default:
            print("⚠️ TypingIndicator: Unknown notification reason")
        }
    }
}