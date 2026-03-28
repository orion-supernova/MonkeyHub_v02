import SwiftUI

struct ConnectionsPanelView: View {
    let friends: [ChatUser]
    let incomingRequests: [FriendRequest]
    let outgoingRequests: [FriendRequest]
    let selectedSection: ChatListViewModel.Section
    let startFriendChat: (ChatUser) -> Void
    let removeFriend: (ChatUser) -> Void
    let approveRequest: (FriendRequest) -> Void
    let rejectRequest: (FriendRequest) -> Void
    let cancelRequest: (FriendRequest) -> Void
    let previewRequest: (FriendRequest) -> Void
    let openOutgoingRequest: (FriendRequest) -> Void

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LazyVStack(spacing: 18) {
            switch selectedSection {
            case .friends:
                friendsSection
            case .requests:
                requestsSection
            case .chats:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var friendsSection: some View {
        Group {
            if friends.isEmpty {
                ContentUnavailableView(
                    "No Friends Yet",
                    systemImage: "person.2.slash",
                    description: Text("Accepted connections will appear here.")
                )
                .padding(.top, 48)
            } else {
                ForEach(friends) { friend in
                    ConnectionUserCard(
                        user: friend,
                        subtitle: "Tap to choose a room type and start chatting.",
                        accent: selectedTheme.colors(for: colorScheme).accent,
                        buttonTitle: "Open",
                        buttonRole: nil,
                        action: { startFriendChat(friend) },
                        removeAction: { removeFriend(friend) }
                    )
                }
            }
        }
    }

    private var requestsSection: some View {
        VStack(spacing: 18) {
            requestGroup(
                title: "Incoming Requests",
                caption: "Approve or deny before the room exists.",
                requests: incomingRequests,
                emptyTitle: "No Incoming Requests"
            ) { request in
                IncomingRequestCard(
                    request: request,
                    approve: { approveRequest(request) },
                    reject: { rejectRequest(request) },
                    preview: { previewRequest(request) }
                )
            }

            requestGroup(
                title: "Sent Requests",
                caption: "These are waiting for the other person.",
                requests: outgoingRequests,
                emptyTitle: "No Pending Requests"
            ) { request in
                OutgoingRequestCard(
                    request: request,
                    cancel: { cancelRequest(request) },
                    open: { openOutgoingRequest(request) }
                )
            }
        }
    }

    private func requestGroup<Content: View>(
        title: String,
        caption: String,
        requests: [FriendRequest],
        emptyTitle: String,
        @ViewBuilder content: @escaping (FriendRequest) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }

            if requests.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "tray")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(requests) { request in
                    content(request)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectionUserCard: View {
    let user: ChatUser
    let subtitle: String
    let accent: Color
    let buttonTitle: String
    let buttonRole: ButtonRole?
    let action: () -> Void
    var removeAction: (() -> Void)? = nil

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }

            Spacer()

            Button(buttonTitle, role: buttonRole, action: action)
                .buttonStyle(.borderedProminent)
                .tint(accent)
            if let removeAction {
                Button("Remove", role: .destructive, action: removeAction)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
    }

    private var avatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: selectedTheme.colors(for: colorScheme).primary,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 48, height: 48)
            .overlay {
                Text(user.displayInitial)
                    .font(.headline.bold())
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
            }
    }
}

private struct IncomingRequestCard: View {
    let request: FriendRequest
    let approve: () -> Void
    let reject: () -> Void
    let preview: () -> Void

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: selectedTheme.colors(for: colorScheme).primary,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                    .overlay {
                        Text(request.user.displayInitial)
                            .font(.headline.bold())
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(request.user.displayName)
                        .font(.headline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    if !request.hasMessages {
                        Text("Friend Request")
                            .font(.footnote)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    } else {
                        Text("\(request.roomType.rawValue) request")
                            .font(.footnote)
                            .foregroundStyle(request.roomType == .secret ? .orange : selectedTheme.colors(for: colorScheme).accent)
                    }
                }

                Spacer()
            }

            if request.hasMessages {
                Text(request.initialMessage.isEmpty ? "Sent \(request.messageCount) message\(request.messageCount == 1 ? "" : "s") — tap Preview to read." : request.initialMessage)
                    .font(.body)
                    .foregroundStyle(request.initialMessage.isEmpty ? selectedTheme.colors(for: colorScheme).textSecondary : selectedTheme.colors(for: colorScheme).textPrimary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(selectedTheme.colors(for: colorScheme).background)
                    )
            }

            HStack(spacing: 10) {
                Button("Deny", role: .destructive, action: reject)
                    .buttonStyle(.bordered)

                if request.hasMessages {
                    Button("Preview", action: preview)
                        .buttonStyle(.borderedProminent)
                        .tint(selectedTheme.colors(for: colorScheme).accent.opacity(0.3))
                }

                Button("Approve", action: approve)
                    .buttonStyle(.borderedProminent)
                    .tint(selectedTheme.colors(for: colorScheme).accent)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(selectedTheme.colors(for: colorScheme).accent.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct OutgoingRequestCard: View {
    let request: FriendRequest
    let cancel: () -> Void
    let open: () -> Void

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(request.user.displayName)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                Spacer()
                Text("Pending")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }

            if request.hasMessages {
                Text(request.initialMessage.isEmpty ? "\(request.messageCount) message\(request.messageCount == 1 ? "" : "s") sent" : request.initialMessage)
                    .font(.footnote)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                if request.hasMessages {
                    Image(systemName: request.roomType == .secret ? "flame.fill" : "bubble.left.and.bubble.right.fill")
                        .foregroundStyle(request.roomType == .secret ? Color.orange : selectedTheme.colors(for: colorScheme).accent)
                    Text(request.roomType.rawValue)
                        .font(.footnote)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                } else {
                    Text("Friend Request")
                        .font(.footnote)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }
                Spacer()
                Button("Open", action: open)
                    .buttonStyle(.borderedProminent)
                    .tint(selectedTheme.colors(for: colorScheme).accent)
                Button("Cancel", role: .destructive, action: cancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
    }
}
