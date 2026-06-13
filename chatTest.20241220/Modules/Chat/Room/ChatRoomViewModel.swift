import SwiftUI
import Combine
import ConvexMobile

@MainActor
class ChatRoomViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isFetchingOlderMessages = false
    @Published private(set) var isFetchingNewMessages = false
    @Published var typingText: String? = nil
    /// The message the composer is currently replying to (nil = not replying).
    @Published var replyingTo: ChatMessage? = nil
    /// Latest "read up to" timestamp among OTHER members — drives the "Seen"
    /// indicator under the last outgoing message (privacy-filtered by backend).
    @Published var othersLastReadAt: Date? = nil

    // Dependencies
    private let repository = ChatRepository.shared
    private let typingManager = TypingIndicatorManager.shared
    private let userDefaults = UserDefaults.standard
    private let userIdUserDefaultsKey = "userId"
    private let userNameUserDefaultsKey = "userName"

    let roomId: String
    private var userId: String = ""
    private var userName: String = "User"
    private var cancellables = Set<AnyCancellable>()
    private var readStateSubscription: AnyCancellable?
    private var canLoadMoreOlderMessages = true

    private struct ReadStateRow: Decodable { let userId: String; let lastReadAt: Double }

    init(roomId: String) {
        self.roomId = roomId
        print("🎬 ChatRoomViewModel init (\(roomId))")

        self.userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let cachedName = ConvexAuthService.shared.cachedUser?.name ?? ConvexAuthService.shared.cachedUser?.username
        self.userName = cachedName ?? userDefaults.string(forKey: userNameUserDefaultsKey) ?? "User"

        setupBindings()
        subscribeToReadState()
        typingManager.setActiveRoom(roomId)
        repository.setActiveRoom(roomId)
    }

    /// Live read-state subscription so the "Seen" indicator updates the moment
    /// the peer reads — not just when this user next sends/receives.
    private func subscribeToReadState() {
        guard !userId.isEmpty else { return }
        readStateSubscription = ConvexService.shared.client
            .subscribe(to: "messages:getReadState",
                       with: ["roomId": roomId, "viewerUserId": userId],
                       yielding: [ReadStateRow].self)
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] rows in
                    guard let self else { return }
                    self.othersLastReadAt = rows
                        .filter { $0.userId != self.userId }
                        .map { Date(timeIntervalSince1970: $0.lastReadAt / 1000) }
                        .max()
                }
            )
    }

    deinit {
        print("💀 ChatRoomViewModel deinit (\(roomId))")
        let roomId = self.roomId
        Task { @MainActor in
            TypingIndicatorManager.shared.stopTyping(in: roomId)
            TypingIndicatorManager.shared.clearIfActive(roomId)
            ChatRepository.shared.clearIfActive(roomId)
        }
    }

    private func setupBindings() {
        repository.$activeRoomMessages
            .receive(on: DispatchQueue.main)
            .map { [roomId] messages in messages.filter { $0.roomId == roomId } }
            .assign(to: \.messages, on: self)
            .store(in: &cancellables)

        typingManager.$typingUsers
            .receive(on: DispatchQueue.main)
            .map { [weak self, roomId] _ in
                self?.typingManager.getTypingText(for: roomId)
            }
            .assign(to: \.typingText, on: self)
            .store(in: &cancellables)
    }

    private var hasLoadedInitialData = false

    func loadMessages() async {
        guard !hasLoadedInitialData else {
            print("✋ ChatRoomViewModel: Data already loaded, skipping refresh")
            return
        }

        isFetchingNewMessages = true
        await repository.fetchMessages(for: roomId)
        isFetchingNewMessages = false

        // ConvexSubscriptionManager is started by setActiveRoom in ChatRepository
        hasLoadedInitialData = true
    }

    func loadOlderMessages() async {
        guard !isFetchingOlderMessages && canLoadMoreOlderMessages else { return }
        isFetchingOlderMessages = true
        let count = await repository.fetchOlderMessages(for: roomId)
        if count == 0 {
            canLoadMoreOlderMessages = false
            print("🏁 ChatRoomViewModel: Reached end of history.")
        }
        isFetchingOlderMessages = false
    }

    // MARK: - Typing Indicator

    func onTextChanged(_ text: String) {
        typingManager.onTextChanged(in: roomId)
    }

    func onSendMessage() {
        typingManager.stopTyping(in: roomId)
    }

    // MARK: - Sending Messages

    func sendMessage(_ text: String) async {
        onSendMessage()
        // Capture and clear the reply target so the next message isn't a reply.
        let parent = replyingTo
        replyingTo = nil
        let message = ChatMessage(
            senderId: userId,
            senderName: userName,
            content: text,
            type: .text,
            roomId: roomId,
            replyToId: parent?.id,
            replyToPreview: parent.map { previewFor($0) }
        )
        await repository.sendMessage(message)
    }

    /// Builds the optimistic denormalized parent snapshot for a reply, matching
    /// what the backend stores so the tether renders before the server echo.
    private func previewFor(_ parent: ChatMessage) -> ReplyPreview {
        let contentPreview: String
        switch parent.type {
        case .image, .video, .audio: contentPreview = parent.content
        default: contentPreview = String(parent.content.prefix(140)) // match backend slice(0,140)
        }
        return ReplyPreview(
            senderId: parent.senderId,
            senderName: parent.senderName,
            contentPreview: contentPreview,
            type: parent.type,
            mediaStorageId: parent.mediaStorageId
        )
    }

    /// Marks the room read up to now (for read receipts). Call on appear / new messages.
    func markRead() async {
        guard !userId.isEmpty else { return }
        try? await ConvexChatAPI.shared.markRoomRead(roomId: roomId, userId: userId)
        await refreshReadState()
    }

    /// Refreshes how far OTHER members have read, for the "Seen" indicator.
    func refreshReadState() async {
        guard !userId.isEmpty else { return }
        guard let state = try? await ConvexChatAPI.shared.fetchReadState(roomId: roomId, viewerUserId: userId) else { return }
        othersLastReadAt = state.filter { $0.key != userId }.values.max()
    }

    /// The id of the most recent message sent by the current user, if it has
    /// been read by another member (used to anchor the "Seen" label).
    var lastSeenOutgoingMessageId: String? {
        guard let readAt = othersLastReadAt else { return nil }
        guard let lastOwn = messages.last(where: { $0.senderId == userId && $0.status == .sent }) else { return nil }
        return readAt >= lastOwn.timestamp ? lastOwn.id : nil
    }

    func sendImage(_ image: PlatformImage) async {
        guard let url = saveTempImage(image) else { return }
        await sendImage(from: url)
    }

    func sendImage(from url: URL) async {
        let localURL = copyAssetToLocalStorage(from: url) ?? url
        guard let data = try? Data(contentsOf: localURL) else {
            AlertManager.shared.showAlert(title: "Error", message: "Could not read image data.")
            return
        }

        // Show the image immediately before upload starts
        let tempId = UUID().uuidString
        repository.insertOptimistic(ChatMessage(
            id: tempId, senderId: userId, senderName: userName,
            content: "📷 Photo", type: .image, roomId: roomId,
            mediaStorageId: nil, assetURL: localURL
        ))

        do {
            let storageId = try await ConvexChatAPI.shared.uploadFile(data: data, mimeType: "image/jpeg")
            ConvexFileCacheService.shared.replaceCachedFile(storageId: storageId, with: localURL)
            // Replace temp optimistic with real one (same id → upsert overwrites it)
            let message = ChatMessage(
                id: tempId, senderId: userId, senderName: userName,
                content: "📷 Photo", type: .image, roomId: roomId,
                mediaStorageId: storageId, assetURL: localURL
            )
            await repository.sendMessage(message)
        } catch {
            repository.failOptimistic(id: tempId, in: roomId)
            AlertManager.shared.showAlert(title: "Error", message: "Failed to send image: \(AppLogger.shared.friendlyError(error))")
        }
    }

    func sendVideo(_ url: URL) async {
        let localURL = copyAssetToLocalStorage(from: url) ?? url

        let tempId = UUID().uuidString
        repository.insertOptimistic(ChatMessage(
            id: tempId, senderId: userId, senderName: userName,
            content: "🎥 Video", type: .video, roomId: roomId,
            mediaStorageId: nil, assetURL: localURL
        ))

        do {
            let storageId = try await ConvexChatAPI.shared.uploadFileFromURL(localURL, mimeType: "video/mp4")
            ConvexFileCacheService.shared.replaceCachedFile(storageId: storageId, with: localURL)
            let message = ChatMessage(
                id: tempId, senderId: userId, senderName: userName,
                content: "🎥 Video", type: .video, roomId: roomId,
                mediaStorageId: storageId, assetURL: localURL
            )
            await repository.sendMessage(message)
        } catch {
            repository.failOptimistic(id: tempId, in: roomId)
            AlertManager.shared.showAlert(title: "Error", message: "Failed to send video: \(AppLogger.shared.friendlyError(error))")
        }
    }

    func sendAudio(_ url: URL) async {
        let localURL = copyAssetToLocalStorage(from: url) ?? url

        let tempId = UUID().uuidString
        repository.insertOptimistic(ChatMessage(
            id: tempId, senderId: userId, senderName: userName,
            content: "🎵 Voice Message", type: .audio, roomId: roomId,
            mediaStorageId: nil, assetURL: localURL
        ))

        do {
            let storageId = try await ConvexChatAPI.shared.uploadFileFromURL(localURL, mimeType: "audio/m4a")
            ConvexFileCacheService.shared.replaceCachedFile(storageId: storageId, with: localURL)
            let message = ChatMessage(
                id: tempId, senderId: userId, senderName: userName,
                content: "🎵 Voice Message", type: .audio, roomId: roomId,
                mediaStorageId: storageId, assetURL: localURL
            )
            await repository.sendMessage(message)
        } catch {
            repository.failOptimistic(id: tempId, in: roomId)
            AlertManager.shared.showAlert(title: "Error", message: "Failed to send voice message: \(AppLogger.shared.friendlyError(error))")
        }
    }

    func deleteMessage(_ messageId: String) async {
        await repository.deleteMessage(messageId, in: roomId)
    }

    // MARK: - Asset Helpers

    private func saveTempImage(_ image: PlatformImage) -> URL? {
        let fileURL = makeAssetFileURL(extension: "jpg")
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

    private func copyAssetToLocalStorage(from sourceURL: URL) -> URL? {
        let fileManager = FileManager.default
        if isInChatAssets(sourceURL) { return sourceURL }

        let fileExtension = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
        let destinationURL = makeAssetFileURL(extension: fileExtension)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            if isLooseTempMediaFileInDocuments(sourceURL) {
                try? fileManager.removeItem(at: sourceURL)
            }
            return destinationURL
        } catch {
            print("Error copying asset to ChatAssets: \(error)")
            return nil
        }
    }

    private func makeAssetFileURL(extension fileExtension: String) -> URL {
        let fileManager = FileManager.default
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let assetsDir = paths[0].appendingPathComponent("ChatAssets", isDirectory: true)
        if !fileManager.fileExists(atPath: assetsDir.path) {
            try? fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        }
        let fileName = UUID().uuidString + "." + fileExtension.lowercased()
        return assetsDir.appendingPathComponent(fileName)
    }

    private func isInChatAssets(_ url: URL) -> Bool {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let assetsDir = documents.appendingPathComponent("ChatAssets", isDirectory: true).path
        return url.path.hasPrefix(assetsDir + "/")
    }

    private func isLooseTempMediaFileInDocuments(_ url: URL) -> Bool {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let isDirectChild = url.deletingLastPathComponent().standardizedFileURL == documents.standardizedFileURL
        guard isDirectChild else { return false }
        return UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }
}
