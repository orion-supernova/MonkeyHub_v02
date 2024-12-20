import AuthenticationServices
import CloudKit
import SwiftUI

enum CloudKitError: LocalizedError {
    case recordNotFound
    case invalidRecord
    case operationFailed
    case networkError
    case permissionDenied
    case notAuthenticated
    case schemaError(String)
    case unknown(Error)

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

    @Published var currentUser: ChatUser? = nil
    @Published var isInitialized = false
    @Published var iCloudStatus: CloudKitStatus = .unknown

    // Schema versioning
    private let versionKey = "version"
    private let currentSchemaVersion = 1

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

        do {
            // 1. Check iCloud availability
            let accountStatus = try await container.accountStatus()

            switch accountStatus {
            case .available:
                Logger.info("iCloud is available", category: .cloudKit)
                iCloudStatus = .available

            case .noAccount:
                Logger.info("No iCloud account", category: .cloudKit)
                iCloudStatus = .noAccount

            case .restricted:
                Logger.error(CloudKitError.permissionDenied, category: .cloudKit)
                iCloudStatus = .restricted

            case .couldNotDetermine:
                Logger.error(CloudKitError.networkError, category: .cloudKit)
                iCloudStatus = .noInternet

            case .temporarilyUnavailable:
                Logger.error(CloudKitError.networkError, category: .cloudKit)
                iCloudStatus = .temporarilyUnavailable

            @unknown default:
                let error = CloudKitError.unknown(NSError())
                Logger.error(error, category: .cloudKit)
                iCloudStatus = .error(error)
            }

        } catch {
            Logger.error(error, category: .cloudKit)
            iCloudStatus = .error(error)
        }

        isInitialized = true
    }

    // MARK: - Authentication
    func signIn(with credential: ASAuthorizationAppleIDCredential) async throws {
        guard case .available = iCloudStatus else {
            throw CloudKitError.notAuthenticated
        }

        // Create user record from Apple ID credential
        let userId = credential.user
        let email = credential.email ?? ""
        let fullName = credential.fullName
        let givenName = fullName?.givenName ?? "User"

        let newRecord = CKRecord(recordType: "ChatUser")
        newRecord["id"] = userId
        newRecord["name"] = givenName
        newRecord["email"] = email

        let savedRecord = try await database.modifyRecords(
            saving: [newRecord], deleting: []
        ).saveResults.first?.1.get()

        guard let record = savedRecord else {
            throw CloudKitError.operationFailed
        }

        currentUser = try ChatUser(from: record)
        userDefaults.set(true, forKey: isAuthenticatedUserDefaultKey)
    }

    func signOut() {
        currentUser = nil
        userDefaults.set(false, forKey: isAuthenticatedUserDefaultKey)
    }

    // MARK: - User Management

    func fetchCurrentUser() async throws -> ChatUser {
        Logger.info(
            "iCloud account available, fetching user record...", category: .cloudKit)
        let userRecordID = try await container.userRecordID()
        Logger.debug("User recordID: \(userRecordID.recordName)", category: .cloudKit)

        // Create a query to find the user record
        let predicate = NSPredicate(format: "id == %@", userRecordID.recordName)
        let query = CKQuery(recordType: "ChatUser", predicate: predicate)

        do {
            Logger.debug("Querying for existing user record...", category: .cloudKit)
            let (records, _) = try await database.records(matching: query)

            if let userRecord = try records.first?.1.get() {
                Logger.info("Existing user record found", category: .cloudKit)
                let user = try ChatUser(from: userRecord)
                currentUser = user
                Logger.info(
                    "User loaded: \(user.name) (\(user.id))", category: .cloudKit)
                return user
            } else {
                Logger.info(
                    "No existing user record found, creating new user...",
                    category: .cloudKit)
                // Create new user record
                let newRecord = CKRecord(recordType: "ChatUser")
                newRecord["id"] = userRecordID.recordName
                newRecord["name"] = "User"
                newRecord["email"] = ""

                do {
                    Logger.debug("Saving new user record...", category: .cloudKit)
                    let saveResult = try await database.modifyRecords(
                        saving: [newRecord], deleting: []
                    ).saveResults.first?.1.get()

                    guard let savedRecord = saveResult else {
                        Logger.error(
                            CloudKitError.operationFailed, category: .cloudKit)
                        throw CloudKitError.operationFailed
                    }

                    let user = try ChatUser(from: savedRecord)
                    currentUser = user
                    Logger.info(
                        "New user created: \(user.name) (\(user.id))",
                        category: .cloudKit)
                    return user
                } catch {
                    Logger.error(error, category: .cloudKit)
                    throw CloudKitError.operationFailed
                }
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
        print("Room record: \(record)")

        let savedRecord = try await database.modifyRecords(saving: [record], deleting: [])
            .saveResults.first?.1.get()
        print("Saved record result: \(String(describing: savedRecord))")

        guard savedRecord != nil else {
            throw CloudKitError.operationFailed
        }
    }

    func fetchChatRooms() async throws -> [ChatRoom] {
        guard let currentUser = currentUser else { throw CloudKitError.notAuthenticated }

        let predicate = NSPredicate(
            format: "%K CONTAINS %@", ChatRoom.participantsKey, currentUser.id)
        let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: ChatRoom.createdAtKey, ascending: false)]

        let (records, _) = try await database.records(matching: query)
        return try records.compactMap { result in
            let record = try result.1.get()
            return try ChatRoom(from: record)
        }
    }

    func fetchAvailableRooms() async throws -> [ChatRoom] {
        guard let currentUser = currentUser else { throw CloudKitError.notAuthenticated }

        let predicate = NSPredicate(
            format: "NOT (%K CONTAINS %@)", ChatRoom.participantsKey, currentUser.id)
        let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: ChatRoom.createdAtKey, ascending: false)]

        let (records, _) = try await database.records(matching: query)
        return try records.compactMap { result in
            let record = try result.1.get()
            return try ChatRoom(from: record)
        }
    }

    func joinRoom(_ room: ChatRoom) async throws {
        guard let currentUser = currentUser else { throw CloudKitError.notAuthenticated }

        let record = room.toRecord()
        var participants = room.participants
        participants.append(currentUser.id)
        record[ChatRoom.participantsKey] = participants

        let savedRecord = try await database.modifyRecords(saving: [record], deleting: [])
            .saveResults.first?.1.get()
        guard savedRecord != nil else {
            throw CloudKitError.operationFailed
        }
    }

    func leaveRoom(_ room: ChatRoom) async throws {
        guard let currentUser = currentUser else { throw CloudKitError.notAuthenticated }

        let record = room.toRecord()
        var participants = room.participants
        participants.removeAll { $0 == currentUser.id }
        record[ChatRoom.participantsKey] = participants

        let savedRecord = try await database.modifyRecords(saving: [record], deleting: [])
            .saveResults.first?.1.get()
        guard savedRecord != nil else {
            throw CloudKitError.operationFailed
        }
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
        let predicate = NSPredicate(format: "%K == %@", ChatMessage.roomIdKey, roomId)
        let subscription = CKQuerySubscription(
            recordType: ChatMessage.recordType,
            predicate: predicate,
            subscriptionID: "messages-\(roomId)",
            options: .firesOnRecordCreation
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let savedSubscription = try await database.modifySubscriptions(
            saving: [subscription], deleting: []
        ).saveResults.first?.1.get()
        guard savedSubscription != nil else {
            throw CloudKitError.operationFailed
        }
    }

    func unsubscribeFromMessages(in roomId: String) async throws {
        try await database.deleteSubscription(withID: "messages-\(roomId)")
    }

    private func updateSchemaIfNeeded() async throws {
        do {
            let query = CKQuery(recordType: "SchemaVersion", predicate: NSPredicate(value: true))
            let (records, _) = try await database.records(matching: query)
            let version = try records.first?.1.get()[versionKey] as? Int ?? 1

            if version < currentSchemaVersion {
                try await migrateSchema(from: version, to: currentSchemaVersion)

                // Update version
                let versionRecord = CKRecord(recordType: "SchemaVersion")
                versionRecord[versionKey] = currentSchemaVersion
                _ = try await database.modifyRecords(
                    saving: [versionRecord],
                    deleting: records.map { try! $0.1.get().recordID }
                )
            }
        } catch let error as CKError where error.code == .unknownItem {
            // SchemaVersion record type doesn't exist yet, create initial version
            Logger.info("Creating initial schema version", category: .cloudKit)

            let versionRecord = CKRecord(recordType: "SchemaVersion")
            versionRecord[versionKey] = currentSchemaVersion

            do {
                _ = try await database.modifyRecords(saving: [versionRecord], deleting: [])
                Logger.info("Schema version initialized", category: .cloudKit)
            } catch {
                Logger.error(error, category: .cloudKit)
                throw CloudKitError.schemaError("Failed to initialize schema version")
            }
        } catch {
            throw error
        }
    }

    private func migrateSchema(from oldVersion: Int, to newVersion: Int) async throws {
        // Implement schema migration logic here if needed
        Logger.info(
            "Migrating schema from v\(oldVersion) to v\(newVersion)", category: .cloudKit)
    }

    func searchRooms(matching query: String) async throws -> [ChatRoom] {
        guard let currentUser = currentUser else { throw CloudKitError.notAuthenticated }

        // Compound predicate to search name and description
        let searchPredicate = NSPredicate(
            format: "name CONTAINS[cd] %@ OR description CONTAINS[cd] %@",
            query, query
        )

        // Only show rooms user isn't already in
        let notMemberPredicate = NSPredicate(
            format: "NOT (%K CONTAINS %@)",
            ChatRoom.participantsKey,
            currentUser.id
        )

        // Combine predicates
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            searchPredicate,
            notMemberPredicate,
        ])

        let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: ChatRoom.createdAtKey, ascending: false)
        ]

        Logger.debug("Executing search query: \(predicate)", category: .database)

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
        guard let currentUser = currentUser else { throw CloudKitError.notAuthenticated }

        let predicate = NSPredicate(
            format: "%K CONTAINS %@",
            ChatRoom.participantsKey,
            currentUser.id
        )

        let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)

        // Dynamic sort based on user preference
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

        Logger.debug("Fetching rooms for user: \(currentUser.id)", category: .database)

        let (records, _) = try await database.records(matching: query)
        return try records.compactMap { result in
            let record = try result.1.get()
            return try ChatRoom(from: record)
        }
    }

    func fetchUsers() async throws -> [ChatUser] {
        guard let currentUser = currentUser else { throw CloudKitError.notAuthenticated }

        let predicate = NSPredicate(
            format: "recordID != %@", currentUser.id
        )
        let query = CKQuery(recordType: "User", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        let (records, _) = try await database.records(matching: query)
        return try records.compactMap { result in
            let record = try result.1.get()
            return try ChatUser(from: record)
        }
    }

    func createChatRoom(name: String, participants: [ChatUser]) async throws {
        guard let currentUser = currentUser else { throw CloudKitError.notAuthenticated }

        let participantIds = participants.map { $0.id } + [currentUser.id]

        let room = ChatRoom(
            name: name,
            createdBy: currentUser.id,
            participants: participantIds
        )

        try await createChatRoom(room)
    }
}
