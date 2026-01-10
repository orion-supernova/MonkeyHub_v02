import CloudKit
import SwiftUI
import Combine

@MainActor
class ChatRoomViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isFetchingOlderMessages = false
    
    // Dependencies
    private let repository = ChatRepository.shared
    private let cloudKit = CloudKitManager.shared
    private let userDefaults = UserDefaults.standard
    private let userIdUserDefaultsKey = "userId"
    
    let roomId: String
    private var userId: String = ""
    private var userName: String = "User"
    private var cancellables = Set<AnyCancellable>()

    init(roomId: String) {
        self.roomId = roomId
        print("🎬 ChatRoomViewModel init (\(roomId))")
        
        self.userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        
        setupBindings()
        repository.setActiveRoom(roomId)
    }
    
    deinit {
        print("💀 ChatRoomViewModel deinit (\(roomId))")
        // Notify repo that we are leaving
        Task { @MainActor in
            ChatRepository.shared.setActiveRoom(nil)
        }
    }

    private func setupBindings() {
        // Bind to Repository messages
        repository.$activeRoomMessages
            .receive(on: DispatchQueue.main)
            .map { [roomId] messages in
                // Only accept messages belonging to this room
                messages.filter { $0.roomId == roomId }
            }
            .assign(to: \.messages, on: self)
            .store(in: &cancellables)
    }

    // Load user data once
    private func loadUserData() async {
        if let user = try? await cloudKit.fetchCurrentUser() {
            self.userName = user.name
        }
    }

    func loadMessages() async {
        await loadUserData()
        // Explicitly wait for fetch to ensure loading state remains true
        await repository.fetchMessages(for: roomId)
        try? await cloudKit.subscribeToMessages(in: roomId)
    }

    func loadOlderMessages() async {
        guard !isFetchingOlderMessages else { return }
        isFetchingOlderMessages = true
        
        await repository.fetchOlderMessages(for: roomId)
        
        isFetchingOlderMessages = false
    }

    func sendMessage(_ text: String) async {
        let message = ChatMessage(
            senderId: userId,
            senderName: userName,
            content: text,
            type: .text,
            roomId: roomId
        )
        await repository.sendMessage(message)
    }
    
    // MARK: - Asset Sending
    
    private func saveTempImage(_ image: PlatformImage) -> URL? {
        let fileManager = FileManager.default
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let assetsDir = paths[0].appendingPathComponent("ChatAssets", isDirectory: true)
        
        if !fileManager.fileExists(atPath: assetsDir.path) {
            try? fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        }
        
        let fileName = UUID().uuidString + ".jpg"
        let fileURL = assetsDir.appendingPathComponent(fileName)
        
        if let data = image.toData() {
            do {
                try data.write(to: fileURL)
                return fileURL
            } catch {
                print("Error saving image to assets: \(error)")
                return nil
            }
        }
        return nil
    }
    
    func sendImage(_ image: PlatformImage) async {
        guard let url = saveTempImage(image) else { return }
        await sendImage(from: url)
    }

    func sendImage(from url: URL) async {
        let message = ChatMessage(
            senderId: userId,
            senderName: userName,
            content: "📷 Photo",
            type: .image,
            roomId: roomId,
            assetURL: url
        )

        // Repository will handle optimistic update (PENDING) -> CloudKit Upload -> Success (SENT)
        await repository.sendMessage(message)
    }

    func sendVideo(_ url: URL) async {
        let message = ChatMessage(
            senderId: userId,
            senderName: userName,
            content: "🎥 Video",
            type: .video,
            roomId: roomId,
            assetURL: url
        )

        await repository.sendMessage(message)
    }

    func sendAudio(_ url: URL) async {
        let message = ChatMessage(
            senderId: userId,
            senderName: userName,
            content: "🎵 Voice Message",
            type: .audio,
            roomId: roomId,
            assetURL: url
        )

        await repository.sendMessage(message)
    }

    func deleteMessage(_ messageId: String) async {
        await repository.deleteMessage(messageId, in: roomId)
    }
}
