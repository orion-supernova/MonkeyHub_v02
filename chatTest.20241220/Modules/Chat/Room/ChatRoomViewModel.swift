import CloudKit
import SwiftUI
import Combine

@MainActor
class ChatRoomViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isFetchingOlderMessages = false
    @Published var typingText: String? = nil
    
    // Dependencies
    private let repository = ChatRepository.shared
    private let cloudKit = CloudKitManager.shared
    private let typingManager = TypingIndicatorManager.shared
    private let userDefaults = UserDefaults.standard
    private let userIdUserDefaultsKey = "userId"
    
    let roomId: String
    private var userId: String = ""
    private var userName: String = "User"
    private var cancellables = Set<AnyCancellable>()
    private var typingCancellable: AnyCancellable?

    init(roomId: String) {
        self.roomId = roomId
        print("🎬 ChatRoomViewModel init (\(roomId))")
        
        self.userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        
        setupBindings()
        repository.setActiveRoom(roomId)
        typingManager.setActiveRoom(roomId)
    }
    
    deinit {
        print("💀 ChatRoomViewModel deinit (\(roomId))")
        
        // Capture roomId for async cleanup
        let roomId = self.roomId
        
        // Stop typing and clean up asynchronously
        Task { @MainActor in
            TypingIndicatorManager.shared.stopTyping(in: roomId)
            TypingIndicatorManager.shared.setActiveRoom(nil)
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
        
        // Bind to typing indicators
        typingManager.$typingUsers
            .receive(on: DispatchQueue.main)
            .map { [weak self, roomId] typingUsers in
                let text = self?.typingManager.getTypingText(for: roomId)
                print("🔄 ChatRoomViewModel: Typing text updated to: \(text ?? "nil")")
                return text
            }
            .assign(to: \.typingText, on: self)
            .store(in: &cancellables)
    }

    // Load user data once
    private func loadUserData() async {
        if let user = try? await cloudKit.fetchCurrentUser() {
            self.userName = user.name
        }
    }

    private var hasLoadedInitialData = false

        func loadMessages() async {
            // 1. EXIT EARLY if we already have data
            // This stops the CloudKit/Database fetch when dismissing images
            guard !hasLoadedInitialData else {
                print("✋ ChatRoomViewModel: Data already loaded, skipping refresh")
                return
            }
            
            await loadUserData()
            
            // 2. This is the expensive call from your logs
            await repository.fetchMessages(for: roomId)
            
            // 3. Subscription is idempotent, but we only need to call it once
            await NotificationSubscriptionManager.shared.subscribeToRoom(roomId)
            
            // 4. Mark as complete
            self.hasLoadedInitialData = true
        }

        private var canLoadMoreOlderMessages = true // ADD THIS

        func loadOlderMessages() async {
            // Stop if already fetching OR if we know there are no more messages
            guard !isFetchingOlderMessages && canLoadMoreOlderMessages else { return }
            
            isFetchingOlderMessages = true
            
            // Update repository to return the count of items found
            let count = await repository.fetchOlderMessages(for: roomId)
            
            if count == 0 {
                self.canLoadMoreOlderMessages = false
                print("🏁 ChatRoomViewModel: Reached end of history.")
            }
            
            isFetchingOlderMessages = false
        }

    // MARK: - Typing Indicator
    func onTextChanged(_ text: String) {
        print("📝 ChatRoomViewModel: Text changed (length: \(text.count))")
        
        // Always notify manager on any text change (including delete)
        typingManager.onTextChanged(in: roomId)
    }
    
    func onSendMessage() {
        print("📤 ChatRoomViewModel: Sending message, stopping typing")
        typingManager.stopTyping(in: roomId)
    }

    func sendMessage(_ text: String) async {
        onSendMessage()
        
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
            content: "📷 Photo",  // This shows in notification
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
            content: "🎥 Video",  // This shows in notification
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
            content: "🎵 Voice Message",  // This shows in notification
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
