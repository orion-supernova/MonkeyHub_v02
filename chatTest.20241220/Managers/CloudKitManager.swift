import AuthenticationServices
import CloudKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum CloudKitError: LocalizedError {
    case recordNotFound
    case invalidRecord
    case operationFailed
    case networkError
    case permissionDenied
    case notAuthenticated
    case schemaError(String)
    case unknown(Error)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .recordNotFound:
            return "The requested item could not be found"
        case .invalidRecord:
            return "Invalid data format"
        case .operationFailed:
            return "Operation could not be completed"
        case .networkError:
            return "Please check your internet connection"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .notAuthenticated:
            return "Please sign in to iCloud in Settings to use this app"
        case .schemaError(let message):
            return "Database setup required: \(message)"
        case .unknown(let error):
            if let ckError = error as? CKError {
                switch ckError.code {
                case .quotaExceeded:
                    return "Storage limit reached. Please free up some iCloud space."
                case .networkUnavailable:
                    return "Network connection required. Please check your internet."
                case .networkFailure:
                    return "Network error. Please try again."
                case .serverResponseLost:
                    return "Connection lost. Please try again."
                default:
                    return "Error: \(ckError.localizedDescription)"
                }
            }
            return error.localizedDescription
        case .custom(let errorMessage):
            return errorMessage
        }
    }

    var developerDescription: String {
        switch self {
        case .unknown(let error):
            if let ckError = error as? CKError {
                return """
                    CloudKit Error:
                    Code: \(ckError.code.rawValue)
                    Description: \(ckError.localizedDescription)
                    Server Message: \(String(describing: ckError.errorUserInfo["CKErrorDescription"] as? String ?? "None"))
                    """
            }
            return "Unknown Error: \(error)"
        default:
            return String(describing: self)
        }
    }
}

@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    // MARK: - Properties
    let container: CKContainer
    let database: CKDatabase

    @Published var isAuthenticated: Bool = false
    @Published var isInitialized = false
    @Published var iCloudStatus: CloudKitStatus = .unknown

    // Schema versioning
    private let versionKey = "version"
    private let currentSchemaVersion = 2  // Updated for v1→v2 migration
    private var hasAttemptedMigration = false  // Prevents duplicate migration attempts

    enum CloudKitStatus {
        case unknown
        case available
        case noAccount
        case restricted
        case noInternet
        case temporarilyUnavailable
        case error(Error)
    }

    private init() {
        self.container = CKContainer(identifier: "iCloud.CrossTest")
        self.database = container.publicCloudDatabase
    }

    // MARK: - Initialization
    func initialize() async {
        Logger.info("Starting CloudKit initialization...", category: .cloudKit)

        // FAST PATH: If we have a stored user ID, assume we are good to go for UI purposes
        if userDefaults.string(forKey: userIdUserDefaultsKey) != nil {
            Logger.info("⚡️ Fast Path: Local user found, unblocking UI immediateley", category: .cloudKit)
            self.isAuthenticated = true
            self.iCloudStatus = .available
            self.isInitialized = true
        } else {
             // If no user, we must block to check status (otherwise LoginView won't know what to show)
             // But we can still be optimistic
        }

        // BACKGROUND CHECK: Verify status without blocking (unless we had no user)
        let checkingTask = Task {
            do {
                // 1. Check iCloud availability
                let accountStatus = try await container.accountStatus()

                await MainActor.run {
                    switch accountStatus {
                    case .available:
                        Logger.info("iCloud is available", category: .cloudKit)
                        self.iCloudStatus = .available
                        
                        // Run schema migrations if needed (only once per app session)
                        if !self.hasAttemptedMigration {
                            self.hasAttemptedMigration = true
                            Task {
                                try? await self.updateSchemaIfNeeded()
                            }
                        } else {
                            Logger.info("⏭️ Skipping migration - already attempted in this session", category: .cloudKit)
                        }

                    case .noAccount:
                        Logger.info("No iCloud account", category: .cloudKit)
                        self.iCloudStatus = .noAccount
                        self.isAuthenticated = false 

                    case .restricted:
                        Logger.error(CloudKitError.permissionDenied, category: .cloudKit)
                        self.iCloudStatus = .restricted
                        self.isAuthenticated = false

                    case .couldNotDetermine:
                        Logger.error(CloudKitError.networkError, category: .cloudKit)
                        self.iCloudStatus = .noInternet

                    case .temporarilyUnavailable:
                        Logger.error(CloudKitError.networkError, category: .cloudKit)
                        self.iCloudStatus = .temporarilyUnavailable

                    @unknown default:
                        let error = CloudKitError.unknown(NSError())
                        Logger.error(error, category: .cloudKit)
                        self.iCloudStatus = .error(error)
                    }
                    
                    // Finalize initialization if not already done via fast path
                    if !self.isInitialized {
                        self.isInitialized = true
                    }
                }

            } catch {
                Logger.error(error, category: .cloudKit)
                await MainActor.run {
                    self.iCloudStatus = .error(error)
                    self.isInitialized = true
                }
            }
        }
        
        // If we didn't take the fast path, await the check (so we don't flash empty UI)
        if !self.isInitialized {
            _ = await checkingTask.result
        }
    }

    // MARK: - Authentication
    func signOut() {
        isAuthenticated = false
        userDefaults.set(nil, forKey: userIdUserDefaultsKey)
    }

    // MARK: - User Management
    func fetchCurrentUser() async throws -> ChatUser {
        Logger.info("Fetching current user record...", category: .cloudKit)
        let userRecordID = try await container.userRecordID()
        Logger.debug("User recordID: \(userRecordID.recordName)", category: .cloudKit)

        // Create a query to find the user record
        let predicate = NSPredicate(
            format: "%K == %@", ChatUser.CodingKeys.id.rawValue, userRecordID.recordName)
        let query = CKQuery(recordType: ChatUser.recordType, predicate: predicate)

        do {
            Logger.debug("Querying for existing user record...", category: .cloudKit)
            let (records, _) = try await database.records(matching: query)

            if let userRecord = try records.first?.1.get() {
                Logger.info("Existing user record found", category: .cloudKit)
                let user = try ChatUser(from: userRecord)
                Logger.info("User loaded: \(user.name) (\(user.id))", category: .cloudKit)
                return user
            } else {
                Logger.error(CloudKitError.recordNotFound, category: .cloudKit)
                throw CloudKitError.recordNotFound
            }
        } catch {
            Logger.error(error, category: .cloudKit)
            throw CloudKitError.unknown(error)
        }
    }

    // MARK: - Chat Room Operations

    func createChatRoom(_ room: ChatRoom) async throws {
        print("Creating room: \(room)")
        let record = room.toRecord()

        // Convert Date to String for createdAt field
        if let createdAt = record[ChatRoom.createdAtKey] as? Date {
            record[ChatRoom.createdAtKey] = formatDateForCloudKit(createdAt)
        }

        print("Room record with formatted date: \(record)")

        do {
            let savedRecord = try await database.modifyRecords(saving: [record], deleting: [])
                .saveResults.first?.1.get()
            print("Saved record result: \(String(describing: savedRecord))")

            guard savedRecord != nil else {
                throw CloudKitError.operationFailed
            }
        } catch let error as CKError {
            Logger.error(
                "Failed to create chat room: \(error.localizedDescription)", category: .cloudKit)

            switch error.code {
            case .networkUnavailable, .networkFailure, .serverResponseLost:
                throw CloudKitError.networkError
            case .permissionFailure:
                throw CloudKitError.permissionDenied
            case .notAuthenticated:
                throw CloudKitError.notAuthenticated
            default:
                throw CloudKitError.unknown(error)
            }
        } catch {
            Logger.error(
                "Unexpected error creating chat room: \(error.localizedDescription)",
                category: .cloudKit)
            throw CloudKitError.unknown(error)
        }
    }

    // MARK: - Date Conversion Helpers

    private func formatDateForCloudKit(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func parseDateFromCloudKit(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    func fetchChatRooms() async throws -> [ChatRoom] {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let predicate = NSPredicate(
            format: "%K CONTAINS %@", ChatRoom.participantsKey, userId)
        let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: ChatRoom.createdAtKey, ascending: false)]

        let (records, _) = try await database.records(matching: query)
        return try records.compactMap { result in
            let record = try result.1.get()
            return try ChatRoom(from: record)
        }
    }

    func fetchAvailableRooms() async throws -> [ChatRoom] {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let predicate = NSPredicate(
            format: "NOT (%K CONTAINS %@)", ChatRoom.participantsKey, userId)
        let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: ChatRoom.createdAtKey, ascending: false)]

        let (records, _) = try await database.records(matching: query)
        return try records.compactMap { result in
            let record = try result.1.get()
            return try ChatRoom(from: record)
        }
    }

    func joinRoom(_ room: ChatRoom) async throws {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        var updatedRoom = room
        if !updatedRoom.participants.contains(userId) {
            updatedRoom.participants.append(userId)
        }
        
        let record = updatedRoom.toRecord()
        _ = try await database.modifyRecords(saving: [record], deleting: [])
            .saveResults.first?.1.get()
        
        // Automatically subscribe to notifications upon joining
        try? await subscribeToMessages(in: room.id)
    }

    func leaveRoom(_ room: ChatRoom) async throws {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        var updatedRoom = room
        updatedRoom.participants.removeAll { $0 == userId }
        
        let record = updatedRoom.toRecord()
        _ = try await database.modifyRecords(saving: [record], deleting: [])
            .saveResults.first?.1.get()
        
        // Unsubscribe from notifications upon leaving
        try? await unsubscribeFromMessages(in: room.id)
    }

    // MARK: - Message Operations

    func sendMessage(_ message: ChatMessage) async throws {
        let record = message.toRecord()
        let savedRecord = try await database.modifyRecords(saving: [record], deleting: [])
            .saveResults.first?.1.get()
        guard savedRecord != nil else {
            throw CloudKitError.operationFailed
        }

        // Update the chat room's last message
        let predicate = NSPredicate(format: "%K == %@", ChatRoom.idKey, message.roomId)
        let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)

        let (records, _) = try await database.records(matching: query)
        if let roomResult = records.first?.1 {
            let roomRecord = try roomResult.get()
            roomRecord[ChatRoom.lastMessageKey] = message.content
            roomRecord[ChatRoom.lastMessageDateKey] = message.timestamp

            let savedRoomRecord = try await database.modifyRecords(
                saving: [roomRecord], deleting: []
            ).saveResults.first?.1.get()
            guard savedRoomRecord != nil else {
                throw CloudKitError.operationFailed
            }
        }
    }

    func fetchMessages(for roomId: String, limit: Int = 50) async throws -> [ChatMessage] {
        let predicate = NSPredicate(format: "%K == %@", ChatMessage.roomIdKey, roomId)
        let query = CKQuery(recordType: ChatMessage.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: ChatMessage.timestampKey, ascending: false)]

        let (records, _) = try await database.records(matching: query, resultsLimit: limit)
        return try records.compactMap { result in
            let record = try result.1.get()
            return try ChatMessage(from: record)
        }
    }

    // MARK: - Asset Handling

    func uploadAsset(data: Data, fileExtension: String) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let fileURL = tempDir.appendingPathComponent(fileName)

        try data.write(to: fileURL)
        return fileURL
    }

    // MARK: - Subscription Management

    func subscribeToMessages(in roomId: String) async throws {
        // Predicate: all messages in this room. 
        // We no longer exclude the sender so that messages sent from one device 
        // trigger real-time updates on other devices owned by the same user.
        let predicate = NSPredicate(format: "%K == %@", ChatMessage.roomIdKey, roomId)

        let subscription = CKQuerySubscription(
            recordType: ChatMessage.recordType,
            predicate: predicate,
            subscriptionID: "messages-\(roomId)",
            options: .firesOnRecordCreation
        )

        let notificationInfo = CKSubscription.NotificationInfo()

        // Enable dynamic notifications with localization templates
        // Template: "%1$@: %2$@" -> "Sender Name: Message Content"
        notificationInfo.alertLocalizationKey = "%1$@: %2$@"
        notificationInfo.alertLocalizationArgs = [ChatMessage.senderNameKey, ChatMessage.contentKey]

        notificationInfo.shouldSendContentAvailable = true  // Background refresh
        notificationInfo.soundName = "default"

        // Include message fields in notification payload
        // Added 'type' to enable proper fallback reconstruction for attachments
        notificationInfo.desiredKeys = [
            ChatMessage.senderNameKey,
            ChatMessage.contentKey,
            ChatMessage.roomIdKey,
            ChatMessage.typeKey  // Critical for attachment handling
        ]
        
        subscription.notificationInfo = notificationInfo

        do {
            let savedSubscription = try await database.modifySubscriptions(
                saving: [subscription], deleting: []
            ).saveResults.first?.1.get()

            guard savedSubscription != nil else {
                throw CloudKitError.operationFailed
            }
            Logger.info("✅ Successfully subscribed to messages in room \(roomId)", category: .cloudKit)
        } catch let error as CKError {
            // Some errors (like duplicate subscription) are expected and shouldn't be treated as failures
            Logger.info("ℹ️ CloudKit subscription info for room \(roomId): \(error.localizedDescription) (Code: \(error.code.rawValue))", category: .cloudKit)
        } catch {
            Logger.error("❌ Subscription failed for room \(roomId): \(error)", category: .cloudKit)
            throw error
        }
    }

    func unsubscribeFromMessages(in roomId: String) async throws {
        try await database.deleteSubscription(withID: "messages-\(roomId)")
    }

    func deleteChatMessage(_ messageId: String) async throws {
        let predicate = NSPredicate(format: "%K == %@", ChatMessage.idKey, messageId)
        let query = CKQuery(recordType: ChatMessage.recordType, predicate: predicate)
        
        let (records, _) = try await database.records(matching: query)
        guard let (recordID, _) = records.first else {
            throw CloudKitError.invalidRecord
        }
        
        try await database.deleteRecord(withID: recordID)
        Logger.info("✅ Deleted message: \(messageId)", category: .cloudKit)
    }

    // MARK: - Push Notification Management

    /// Update the current user's device token in CloudKit
    ///
    /// This method syncs the APNs device token to the user's CloudKit record,
    /// enabling push notifications for chatroom messages.
    ///
    /// - Parameter token: The APNs device token as a hex string
    func updateDeviceToken(_ token: String) async {
        // Store token locally first to ensure it survives if network fails or user is not logged in
        userDefaults.set(token, forKey: "deviceToken")
        
        Logger.info("Updating device token in CloudKit", category: .cloudKit)

        do {
            let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
            guard !userId.isEmpty else {
                Logger.warning("Cannot sync device token: userId is missing (user likely not logged in yet)", category: .cloudKit)
                return
            }
            
            let predicate = NSPredicate(format: "%K == %@", ChatUser.CodingKeys.id.rawValue, userId)
            let query = CKQuery(recordType: ChatUser.recordType, predicate: predicate)

            let (records, _) = try await database.records(matching: query)
            guard let existingRecord = try records.first?.1.get() else {
                Logger.error("User record not found for device token update", category: .cloudKit)
                return
            }

            // Only update if it changed
            let currentToken = existingRecord[ChatUser.CodingKeys.deviceToken.rawValue] as? String
            if currentToken != token {
                existingRecord[ChatUser.CodingKeys.deviceToken.rawValue] = token
                try await database.modifyRecords(saving: [existingRecord], deleting: [])
                Logger.info("Device token updated successfully in CloudKit", category: .cloudKit)
            } else {
                Logger.info("Device token already up to date in CloudKit", category: .cloudKit)
            }
        } catch {
            Logger.error("Failed to update device token: \(error)", category: .cloudKit)
        }
    }

    /// Sync the locally stored device token with CloudKit
    ///
    /// This should be called after a successful login to ensure the token
    /// received during app launch is associated with the user record.
    func syncDeviceTokenWithCloudKit() async {
        guard let token = userDefaults.string(forKey: "deviceToken") else {
            Logger.info("No local device token to sync", category: .cloudKit)
            return
        }
        await updateDeviceToken(token)
    }

    /// Subscribe to all rooms the user has joined
    ///
    /// This is useful after a reinstall to restore push notification subscriptions.
    func subscribeToAllJoinedRooms() async {
        Logger.info("Restoring subscriptions for all joined rooms", category: .cloudKit)
        do {
            let rooms = try await fetchUserRooms()
            for room in rooms {
                try? await subscribeToMessages(in: room.id)
            }
            Logger.info("Restored \(rooms.count) room subscriptions", category: .cloudKit)
        } catch {
            Logger.error("Failed to restore room subscriptions: \(error)", category: .cloudKit)
        }
    }

    /// Check schema version and run migrations if needed
    ///
    /// This function should be called during app initialization to ensure
    /// the CloudKit schema is up to date.
    func updateSchemaIfNeeded() async throws {
        Logger.info("Checking schema version...", category: .cloudKit)

        do {
            // Fetch current schema version
            let recordID = CKRecord.ID(recordName: SchemaVersion.recordName)
            let record = try await database.record(for: recordID)
            let schemaVersion = try SchemaVersion(from: record)

            Logger.info("Current schema version: \(schemaVersion.version)", category: .cloudKit)

            // Check if migration is needed
            if schemaVersion.version < currentSchemaVersion {
                Logger.info(
                    "Migration needed: v\(schemaVersion.version) → v\(currentSchemaVersion)",
                    category: .cloudKit)
                try await migrateSchema(from: schemaVersion.version, to: currentSchemaVersion)
            } else {
                Logger.info("Schema is up to date", category: .cloudKit)
            }

        } catch let error as CKError where error.code == .unknownItem {
            // SchemaVersion record doesn't exist yet - this is a fresh install
            Logger.info("No schema version record found - creating initial version", category: .cloudKit)

            // Get persistent device identifier
            let deviceId: String
            #if os(iOS) || os(tvOS)
            if let uuid = UIDevice.current.identifierForVendor?.uuidString {
                deviceId = String(uuid.prefix(8))
            } else {
                // Fallback: Use persistent identifier from UserDefaults
                let key = "com.app.deviceIdentifier"
                if let stored = UserDefaults.standard.string(forKey: key) {
                    deviceId = stored
                } else {
                    let newId = "Device-\(UUID().uuidString.prefix(8))"
                    UserDefaults.standard.set(newId, forKey: key)
                    deviceId = newId
                }
            }
            #else
            // macOS/visionOS: Use persistent identifier from UserDefaults
            let key = "com.app.deviceIdentifier"
            if let stored = UserDefaults.standard.string(forKey: key) {
                deviceId = stored
            } else {
                let newId = "Device-\(UUID().uuidString.prefix(8))"
                UserDefaults.standard.set(newId, forKey: key)
                deviceId = newId
            }
            #endif

            let schemaVersion = SchemaVersion(
                version: currentSchemaVersion,
                migrationHistory: "[]",
                lastMigrationDate: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
                deviceIdentifier: deviceId
            )

            let record = schemaVersion.toRecord()
            _ = try await database.modifyRecords(saving: [record], deleting: [])
            Logger.info("Schema version initialized to v\(currentSchemaVersion)", category: .cloudKit)

        } catch {
            Logger.error("Failed to check schema version: \(error)", category: .cloudKit)
            throw error
        }
    }

    /// Execute schema migration using MigrationRunner
    ///
    /// - Parameters:
    ///   - oldVersion: Current schema version
    ///   - newVersion: Target schema version
    private func migrateSchema(from oldVersion: Int, to newVersion: Int) async throws {
        Logger.info("Starting migration from v\(oldVersion) to v\(newVersion)", category: .cloudKit)

        let runner = MigrationRunner(database: database)

        do {
            try await runner.migrate(to: newVersion)
            Logger.info("Migration completed successfully", category: .cloudKit)
        } catch {
            Logger.error("Migration failed: \(error)", category: .cloudKit)
            throw CloudKitError.schemaError("Migration failed: \(error.localizedDescription)")
        }
    }

    func searchRooms(matching query: String) async throws -> [ChatRoom] {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""

        // Simple tokenized search using the supported 'CONTAINS' operator
        let predicate = NSPredicate(
            format: "self CONTAINS %@ AND NOT(participants CONTAINS %@)",
            query, userId)

        print("🔍 Room search predicate: \(predicate.predicateFormat)")

        let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: ChatRoom.createdAtKey, ascending: false)
        ]

        let (records, _) = try await database.records(matching: query)
        return try records.compactMap { try ChatRoom(from: try $0.1.get()) }
    }

    func fetchRecentMessages(for roomId: String, before date: Date? = nil, limit: Int = 50)
        async throws -> [ChatMessage]
    {
        var predicates: [NSPredicate] = [
            NSPredicate(format: "%K == %@", ChatMessage.roomIdKey, roomId)
        ]

        if let date = date {
            predicates.append(
                NSPredicate(
                    format: "%K < %@", ChatMessage.timestampKey, date as CVarArg
                ))
        }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let query = CKQuery(recordType: ChatMessage.recordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: ChatMessage.timestampKey, ascending: false)
        ]

        Logger.debug("Fetching messages for room: \(roomId)", category: .database)

        let (records, cursor) = try await database.records(
            matching: query,
            resultsLimit: limit
        )
        return try records.compactMap { try ChatMessage(from: try $0.1.get()) }
    }

    func fetchUserRooms(sortBy: ChatRoomSortOption = .lastActivity) async throws -> [ChatRoom] {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let predicate = NSPredicate(
            format: "%K CONTAINS %@",
            ChatRoom.participantsKey,
            userId
        )

        let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)

        switch sortBy {
        case .lastActivity:
            query.sortDescriptors = [
                NSSortDescriptor(key: ChatRoom.lastMessageDateKey, ascending: false)
            ]
        case .name:
            query.sortDescriptors = [
                NSSortDescriptor(key: ChatRoom.nameKey, ascending: true)
            ]
        case .created:
            query.sortDescriptors = [
                NSSortDescriptor(key: ChatRoom.createdAtKey, ascending: false)
            ]
        }

        Logger.debug("Fetching rooms for user: \(userId)", category: .database)

        let (records, _) = try await database.records(matching: query)
        return try records.compactMap { result in
            let record = try result.1.get()
            return try ChatRoom(from: record)
        }
    }

    func fetchUsers() async throws -> [ChatUser] {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let predicate = NSPredicate(
            format: "%K != %@", ChatUser.CodingKeys.id.rawValue, userId
        )
        let query = CKQuery(recordType: ChatUser.recordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: ChatUser.CodingKeys.name.rawValue, ascending: true)
        ]

        let (records, _) = try await database.records(matching: query)
        return try records.compactMap { result in
            let record = try result.1.get()
            return try ChatUser(from: record)
        }
    }

    func createChatRoom(name: String, participants: [ChatUser]) async throws {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let participantIds = participants.map { $0.id } + [userId]

        let room = ChatRoom(
            name: name,
            createdBy: userId,
            participants: participantIds
        )

        try await createChatRoom(room)
    }

    func updateUser(_ user: ChatUser) async throws {
        let predicate = NSPredicate(format: "%K == %@", ChatUser.CodingKeys.id.rawValue, user.id)
        let query = CKQuery(recordType: ChatUser.recordType, predicate: predicate)

        do {
            let (records, _) = try await database.records(matching: query)
            guard let existingRecord = try records.first?.1.get() else {
                throw CloudKitError.recordNotFound
            }

            existingRecord[ChatUser.CodingKeys.name.rawValue] = user.name
            existingRecord[ChatUser.CodingKeys.username.rawValue] = user.username
            existingRecord[ChatUser.CodingKeys.email.rawValue] = user.email
            if let avatar = user.avatarAsset {
                existingRecord[ChatUser.CodingKeys.avatar.rawValue] = avatar
            }

            let modifyOperation = CKModifyRecordsOperation(
                recordsToSave: [existingRecord],
                recordIDsToDelete: nil
            )
            modifyOperation.savePolicy = .changedKeys
            modifyOperation.qualityOfService = .userInitiated

            try await database.modifyRecords(saving: [existingRecord], deleting: [])

            Logger.info("User updated successfully: \(user.name)", category: .cloudKit)
        } catch {
            Logger.error("Failed to update user: \(error)", category: .cloudKit)
            throw error
        }
    }

    private func createAsset(from image: UIImage) throws -> CKAsset {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw CloudKitError.custom("Failed to compress image")
        }

        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".jpg"
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        try imageData.write(to: fileURL)

        return CKAsset(fileURL: fileURL)
    }

    func updateUserProfilePicture(_ user: ChatUser, image: UIImage?) async throws {
        let predicate = NSPredicate(format: "%K == %@", ChatUser.CodingKeys.id.rawValue, user.id)
        let query = CKQuery(recordType: ChatUser.recordType, predicate: predicate)

        do {
            let (records, _) = try await database.records(matching: query)
            guard let existingRecord = try records.first?.1.get() else {
                throw CloudKitError.recordNotFound
            }

            if let image = image {
                let asset = try createAsset(from: image)
                existingRecord[ChatUser.CodingKeys.avatar.rawValue] = asset
            } else {
                existingRecord[ChatUser.CodingKeys.avatar.rawValue] = nil
            }

            try await database.modifyRecords(saving: [existingRecord], deleting: [])
            Logger.info("User profile picture updated successfully", category: .cloudKit)
        } catch {
            Logger.error("Failed to update profile picture: \(error)", category: .cloudKit)
            throw error
        }
    }

    func searchUsers(matching query: String) async throws -> [ChatUser] {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""

        // Simple tokenized search using the supported 'CONTAINS' operator
        let predicate = NSPredicate(format: "self CONTAINS %@ AND NOT(id = %@)", query, userId)

        print("🔍 User search predicate: \(predicate.predicateFormat)")

        let query = CKQuery(recordType: ChatUser.recordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: ChatUser.CodingKeys.name.rawValue, ascending: true)
        ]

        let (records, _) = try await database.records(matching: query)
        return try records.compactMap { try ChatUser(from: try $0.1.get()) }
    }
}
