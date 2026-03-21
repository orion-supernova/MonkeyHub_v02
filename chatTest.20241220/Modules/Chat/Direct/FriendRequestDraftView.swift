import SwiftUI

struct FriendRequestDraftView: View {
    @Environment(\.dismiss) private var dismiss

    let session: DraftDirectChatSession

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    @State private var draftText = ""
    @State private var pendingConfirmationText: String?
    @State private var requestId: String?
    @State private var requestSubmitted = false
    @State private var isSubmitting = false

    // Tracks whether we've confirmed the outgoing request exists in the live list at least once,
    // to avoid a false-positive rejection when the subscription hasn't delivered data yet.
    @State private var requestSeenInOutgoing: Bool
    // Set to true once we've initiated a room transition to prevent double-navigation.
    @State private var hasTransitioned = false
    // Set to true when the request disappears without a room (rejected or cancelled by receiver).
    @State private var requestRejected = false
    // Holds the initial message optimistically while we wait for the subscription to deliver it.
    @State private var optimisticMessages: [FriendRequestMessage] = []

    @ObservedObject private var repository = ChatRepository.shared

    init(session: DraftDirectChatSession) {
        self.session = session
        self._requestId = State(initialValue: session.requestId)
        self._requestSubmitted = State(initialValue: session.requestId != nil)
        // If we already have a requestId, we know it exists — no need to wait for first
        // outgoing-requests delivery before considering a disappearance meaningful.
        self._requestSeenInOutgoing = State(initialValue: session.requestId != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    statusBanner

                    messageList
                    if repository.activeRequestMessages.isEmpty && optimisticMessages.isEmpty {
                        ContentUnavailableView(
                            "No Messages Yet",
                            systemImage: session.roomType == .secret ? "flame.fill" : "bubble.left",
                            description: Text("Your first message becomes the friend request once you confirm it.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(20)
            }

            composer
        }
        .background(selectedTheme.colors(for: colorScheme).background)
        .navigationTitle(session.user.displayName)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if let requestId {
                repository.setActiveRequest(requestId)
            }
        }
        .onDisappear {
            repository.setActiveRequest(nil)
        }
        // When a DM room for this conversation appears, the request was accepted — go there.
        .onChange(of: repository.rooms) { _, newRooms in
            guard requestSubmitted, !hasTransitioned else { return }
            let userId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""
            let names = dmRoomNames(userId: userId, friendId: session.user.id)
            guard let room = newRooms.first(where: { names.contains($0.name) }) else { return }
            hasTransitioned = true
            // Replace this draft destination with the real chat room in the nav stack.
            guard !NavigationStateManager.shared.path.isEmpty else { return }
            NavigationStateManager.shared.path.removeLast()
            NavigationStateManager.shared.path.append(room)
        }
        // When the outgoing request disappears without a room, it was rejected or cancelled.
        .onChange(of: repository.outgoingRequests) { _, newRequests in
            guard requestSubmitted, !hasTransitioned else { return }
            guard let requestId else { return }
            if newRequests.contains(where: { $0.id == requestId }) {
                requestSeenInOutgoing = true
                return
            }
            // Only act on disappearance once we've confirmed the request was in the list,
            // preventing a false trigger on initial subscription delivery when list is empty.
            guard requestSeenInOutgoing else { return }
            let userId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""
            let names = dmRoomNames(userId: userId, friendId: session.user.id)
            // If the room already exists the rooms observer will handle navigation.
            guard repository.rooms.first(where: { names.contains($0.name) }) == nil else { return }
            hasTransitioned = true
            requestRejected = true
        }
        .alert("Send Friend Request?", isPresented: Binding(
            get: { pendingConfirmationText != nil },
            set: { if !$0 { pendingConfirmationText = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingConfirmationText = nil
            }
            Button("Send Request") {
                // Capture synchronously — the alert dismissal binding sets
                // pendingConfirmationText to nil before the async task body runs.
                if let text = pendingConfirmationText {
                    pendingConfirmationText = nil
                    Task { await confirmFriendRequest(pendingText: text) }
                }
            }
        } message: {
            Text("The request will be sent with this first message. The room will only be created after \(session.user.displayName) accepts.")
        }
        .alert("Request Resolved", isPresented: $requestRejected) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your request to \(session.user.displayName) is no longer pending.")
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 54, height: 54)
                .overlay {
                    Text(session.user.displayInitial)
                        .font(.title2.bold())
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(session.roomType.rawValue)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                if session.roomType == .secret, let lifetime = session.messageLifetime {
                    Text("Messages will expire after \(formatLifetime(lifetime)) once approved.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else {
                    Text("This will become a standard private chat once approved.")
                        .font(.footnote)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }
            }

            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
    }

    private var statusBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: requestSubmitted ? "clock.badge.fill" : "paperplane.circle.fill")
                .font(.title3)
                .foregroundStyle(requestSubmitted ? Color.orange : selectedTheme.colors(for: colorScheme).accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(requestSubmitted ? "Pending Request" : "Friend request will be sent with your first message.")
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                Text(
                    requestSubmitted
                        ? "\(session.user.displayName) will see your request in their Requests screen."
                        : "Nothing is stored in the chat database until you confirm the first message."
                )
                .font(.footnote)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    requestSubmitted ? Color.orange.opacity(0.45) : selectedTheme.colors(for: colorScheme).accent.opacity(0.3),
                    lineWidth: 1.5
                )
        )
    }

    private var messageList: some View {
        // Show optimistic messages while waiting for the subscription to deliver server data.
        let messages = repository.activeRequestMessages.isEmpty
            ? optimisticMessages
            : repository.activeRequestMessages
        return VStack(spacing: 12) {
            ForEach(messages) { message in
                messageBubble(message)
            }
        }
    }

    private func messageBubble(_ message: FriendRequestMessage) -> some View {
        let isSender = message.userId == UserDefaults.standard.string(forKey: userIdUserDefaultsKey)
        return HStack {
            if isSender { Spacer(minLength: 60) }
            Text(message.content)
                .font(.body)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            isSender
                                ? AnyShapeStyle(LinearGradient(
                                    colors: selectedTheme.colors(for: colorScheme).primary,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                  ))
                                : AnyShapeStyle(selectedTheme.colors(for: colorScheme).cardBackground)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            isSender
                                ? Color.clear
                                : selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.2),
                            lineWidth: 1
                        )
                )
            if !isSender { Spacer(minLength: 60) }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if requestSubmitted {
                Text("Pending request")
                    .font(.footnote)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    .padding(.top, 8)
            }

            HStack(spacing: 12) {
                TextField("Write your first message", text: $draftText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                    )

                Button {
                    let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if requestId == nil {
                        pendingConfirmationText = trimmed
                    } else {
                        Task {
                            await appendMessage(trimmed)
                        }
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.title3.bold())
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: selectedTheme.colors(for: colorScheme).primary,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(selectedTheme.colors(for: colorScheme).background)
    }

    private func confirmFriendRequest(pendingText: String) async {
        let userId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""
        guard !userId.isEmpty else { return }

        isSubmitting = true
        do {
            let createdId = try await ConvexChatAPI.shared.createDirectRequest(
                userId: userId,
                friendId: session.user.id,
                roomType: session.roomType,
                messageLifetime: session.messageLifetime,
                initialMessage: pendingText
            )
            requestId = createdId
            requestSubmitted = true
            requestSeenInOutgoing = true
            draftText = ""

            // Show the message immediately — don't wait for the subscription to deliver it.
            optimisticMessages = [FriendRequestMessage(
                id: UUID().uuidString,
                userId: userId,
                content: pendingText,
                createdAt: Date()
            )]

            repository.setActiveRequest(createdId)
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: AppLogger.shared.friendlyError(error))
        }
        isSubmitting = false
    }

    private func appendMessage(_ content: String) async {
        guard let requestId else { return }
        let userId = UserDefaults.standard.string(forKey: userIdUserDefaultsKey) ?? ""
        guard !userId.isEmpty else { return }

        isSubmitting = true
        do {
            try await ConvexChatAPI.shared.appendDirectRequestMessage(
                requestId: requestId,
                userId: userId,
                content: content
            )
            draftText = ""
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: AppLogger.shared.friendlyError(error))
        }
        isSubmitting = false
    }

    /// Returns the possible DM room name(s) for this conversation. The backend uses
    /// `dm:<type>:<sorted_id1>:<sorted_id2>`, with a legacy fallback for regular rooms.
    private func dmRoomNames(userId: String, friendId: String) -> [String] {
        let roomKey = session.roomType == .secret ? "secret" : "regular"
        let ordered = [userId, friendId].sorted()
        var names = ["dm:\(roomKey):\(ordered[0]):\(ordered[1])"]
        if session.roomType == .regular {
            names.append("dm:\(ordered[0]):\(ordered[1])")  // legacy format
        }
        return names
    }

    private func formatLifetime(_ lifetime: TimeInterval) -> String {
        let seconds = Int(lifetime)
        if seconds >= 3600 {
            return "\(seconds / 3600) hour" + (seconds >= 7200 ? "s" : "")
        }
        if seconds >= 60 {
            return "\(seconds / 60) minute" + (seconds >= 120 ? "s" : "")
        }
        return "\(seconds) second" + (seconds == 1 ? "" : "s")
    }
}
