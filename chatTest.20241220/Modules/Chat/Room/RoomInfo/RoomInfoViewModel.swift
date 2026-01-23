import CloudKit
import SwiftUI
import Combine

@MainActor
final class RoomInfoViewModel: ObservableObject {
    @Published var room: ChatRoom
    @Published private(set) var members: [ChatUser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUploadingAvatar = false
    @Published private(set) var error: CloudKitError?
    
    private let cloudKit = CloudKitManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init(room: ChatRoom) {
        self.room = room
    }
    
    func refreshRoom() async {
        isLoading = true
        error = nil
        
        do {
            let recordId = CKRecord.ID(recordName: room.id)
            let record = try await cloudKit.database.record(for: recordId)
            room = try ChatRoom(from: record)
            isLoading = false
        } catch {
            self.error = error as? CloudKitError ?? .unknown(error)
            isLoading = false
        }
    }
    
    func loadMembers() async {
        isLoading = true
        error = nil
        
        do {
            // Fetch current user first
            let currentUser = try await cloudKit.fetchCurrentUser()
            
            // Fetch all other users
            let allUsers = try await cloudKit.fetchUsers()
            
            // Combine current user with other members
            var allMembers = allUsers.filter { user in
                room.participants.contains(user.id)
            }
            
            // Add current user if they're a participant and not already in the list
            if room.participants.contains(currentUser.id),
               !allMembers.contains(where: { $0.id == currentUser.id }) {
                allMembers.append(currentUser)
            }
            
            members = allMembers
            isLoading = false
        } catch {
            self.error = error as? CloudKitError ?? .unknown(error)
            isLoading = false
        }
    }
    
    func updateRoomAvatar(_ image: PlatformImage) async {
        print("🖼️ RoomInfoViewModel: updateRoomAvatar called")
        print("🖼️ RoomInfoViewModel: Room ID: \(room.id)")
        print("🖼️ RoomInfoViewModel: Room Name: \(room.name)")
        isUploadingAvatar = true
        error = nil

        do {
            print("🖼️ RoomInfoViewModel: Creating asset from image...")
            let asset = try createAsset(from: image)
            print("🖼️ RoomInfoViewModel: Asset created at: \(asset.fileURL?.path ?? "unknown")")

            // Query by the "id" field, not recordID
            print("🖼️ RoomInfoViewModel: Querying room by id field: \(room.id)")
            let predicate = NSPredicate(format: "%K == %@", ChatRoom.idKey, room.id)
            let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)

            let (records, _) = try await cloudKit.database.records(matching: query, resultsLimit: 1)
            guard let record = try records.first?.1.get() else {
                print("❌ RoomInfoViewModel: Room not found with id: \(room.id)")
                throw CloudKitError.recordNotFound
            }

            print("✅ RoomInfoViewModel: Room found! Record ID: \(record.recordID.recordName)")

            record[ChatRoom.avatarAssetKey] = asset

            print("🖼️ RoomInfoViewModel: Saving record with avatar...")
            _ = try await cloudKit.database.modifyRecords(saving: [record], deleting: [])
            print("🖼️ RoomInfoViewModel: Avatar saved to CloudKit successfully")

            // Refresh room to get updated avatarAsset
            let (updatedRecords, _) = try await cloudKit.database.records(matching: query, resultsLimit: 1)
            if let updatedRecord = try updatedRecords.first?.1.get() {
                room = try ChatRoom(from: updatedRecord)
                print("🖼️ RoomInfoViewModel: Room refreshed with new avatar")
            }

            // Send system message about avatar change
            await sendAvatarChangeMessage()

            isUploadingAvatar = false
        } catch let error as CKError {
            print("❌ RoomInfoViewModel: CloudKit error: \(error)")
            self.error = .unknown(error)
            isUploadingAvatar = false
        } catch {
            print("❌ RoomInfoViewModel: Failed to update avatar: \(error)")
            self.error = error as? CloudKitError ?? .unknown(error)
            isUploadingAvatar = false
        }
    }
    
    func updateRoomName(_ newName: String) async {
        guard !newName.isEmpty, newName != room.name else { return }
        
        isLoading = true
        error = nil
        
        let oldName = room.name
        
        do {
            let recordId = CKRecord.ID(recordName: room.id)
            let record = try await cloudKit.database.record(for: recordId)
            record[ChatRoom.nameKey] = newName
            
            _ = try await cloudKit.database.modifyRecords(saving: [record], deleting: [])
            
            // Refresh the room data
            room = try ChatRoom(from: try await cloudKit.database.record(for: recordId))
            
            // Send system message about name change
            await sendNameChangeMessage(oldName: oldName, newName: newName)
            
            isLoading = false
        } catch {
            self.error = error as? CloudKitError ?? .unknown(error)
            isLoading = false
        }
    }
    
    func updateRoomDescription(_ newDescription: String) async {
        let trimmedDescription = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDescription != (room.description ?? "") else { return }
        
        isLoading = true
        error = nil
        
        let oldDescription = room.description
        
        do {
            let recordId = CKRecord.ID(recordName: room.id)
            let record = try await cloudKit.database.record(for: recordId)
            
            if trimmedDescription.isEmpty {
                record[ChatRoom.descriptionKey] = nil
            } else {
                record[ChatRoom.descriptionKey] = trimmedDescription
            }
            
            _ = try await cloudKit.database.modifyRecords(saving: [record], deleting: [])
            
            // Refresh the room data
            room = try ChatRoom(from: try await cloudKit.database.record(for: recordId))
            
            // Send system message about description change
            await sendDescriptionChangeMessage(oldDescription: oldDescription, newDescription: trimmedDescription)
            
            isLoading = false
        } catch {
            self.error = error as? CloudKitError ?? .unknown(error)
            isLoading = false
        }
    }
    
    func updateRoomPrivacy(_ isPrivate: Bool) async {
        isLoading = true
        error = nil
        
        do {
            let recordId = CKRecord.ID(recordName: room.id)
            let record = try await cloudKit.database.record(for: recordId)
            record[ChatRoom.isPrivateKey] = isPrivate
            
            _ = try await cloudKit.database.modifyRecords(saving: [record], deleting: [])
            
            var updatedRoom = room
            updatedRoom.isPrivate = isPrivate
            room = updatedRoom
            
            // Send system message about privacy change
            await sendPrivacyChangeMessage(isPrivate: isPrivate)
            
            isLoading = false
        } catch {
            self.error = error as? CloudKitError ?? .unknown(error)
            isLoading = false
        }
    }
    
    private func sendAvatarChangeMessage() async {
        let currentUserName = await fetchCurrentUserName()
        let content = "\(currentUserName) updated the room avatar"
        await sendSystemMessage(content)
    }
    
    private func sendNameChangeMessage(oldName: String, newName: String) async {
        let currentUserName = await fetchCurrentUserName()
        let content = "\(currentUserName) changed the room name from \"\(oldName)\" to \"\(newName)\""
        await sendSystemMessage(content)
    }
    
    private func sendDescriptionChangeMessage(oldDescription: String?, newDescription: String) async {
        let currentUserName = await fetchCurrentUserName()
        
        let content: String
        if let oldDesc = oldDescription, !oldDesc.isEmpty {
            if newDescription.isEmpty {
                content = "\(currentUserName) removed the room description"
            } else {
                content = "\(currentUserName) updated the room description"
            }
        } else {
            content = "\(currentUserName) added a room description"
        }
        
        await sendSystemMessage(content)
    }
    
    private func sendPrivacyChangeMessage(isPrivate: Bool) async {
        let currentUserName = await fetchCurrentUserName()
        let content = isPrivate 
            ? "\(currentUserName) made this room private" 
            : "\(currentUserName) made this room public"
        await sendSystemMessage(content)
    }
    
    private func fetchCurrentUserName() async -> String {
        do {
            let user = try await cloudKit.fetchCurrentUser()
            return user.name
        } catch {
            return "Someone"
        }
    }
    
    private func sendSystemMessage(_ content: String) async {
        let systemMessage = ChatMessage(
            senderId: ChatMessage.systemSenderId,
            senderName: ChatMessage.systemSenderName,
            content: content,
            type: .system,
            roomId: room.id
        )
        
        try? await cloudKit.sendMessage(systemMessage)
    }
    
    private func createAsset(from image: PlatformImage) throws -> CKAsset {
        guard let data = image.toData() else {
            throw CloudKitError.operationFailed
        }
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".jpg"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        try data.write(to: fileURL)
        
        return CKAsset(fileURL: fileURL)
    }
    
    func removeMember(_ userId: String) async {
        isLoading = true
        error = nil
        
        do {
            var updatedRoom = room
            updatedRoom.participants.removeAll { $0 == userId }
            
            let record = updatedRoom.toRecord()
            _ = try await cloudKit.database.modifyRecords(saving: [record], deleting: [])
            
            room = updatedRoom
            members.removeAll { $0.id == userId }
            isLoading = false
        } catch {
            self.error = error as? CloudKitError ?? .unknown(error)
            isLoading = false
        }
    }
}