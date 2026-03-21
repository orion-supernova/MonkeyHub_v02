import SwiftUI

struct UsersListView: View {
    let users: [ChatUser]
    let selectUser: (ChatUser) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            if users.isEmpty {
                emptyStateView
            } else {
                ForEach(users) { user in
                    UserRow(user: user, selectUser: selectUser)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("No Users Found")
                .font(.title2.bold())
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

            Text("Try searching with different keywords")
                .font(.subheadline)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

struct UserRow: View {
    let user: ChatUser
    let selectUser: (ChatUser) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @State private var avatarImage: PlatformImage?
    @State private var isLoadingAvatar = false

    var body: some View {
        Button {
            Task {
                await selectUser(user)
            }
        } label: {
            HStack(spacing: 16) {
                userAvatar
                userInfo
                Spacer()
                messageIcon
            }
            .padding()
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
        .task(id: user.avatarStorageId) {
            avatarImage = nil
            guard let storageId = user.avatarStorageId else { return }
            isLoadingAvatar = true
            if let image = await ConvexFileCacheService.shared.image(for: storageId) {
                avatarImage = image
            }
            isLoadingAvatar = false
        }
    }

    private var userAvatar: some View {
        ZStack {
            if let image = avatarImage {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: selectedTheme.colors(for: colorScheme).primary,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay {
                        if isLoadingAvatar {
                            ProgressView()
                                .tint(selectedTheme.colors(for: colorScheme).text)
                                .scaleEffect(0.8)
                        } else {
                            Text(user.displayInitial)
                                .font(.title3.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                        }
                    }
            }
        }
        .frame(width: 44, height: 44)
        .shadow(color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.2), radius: 4, y: 2)
    }

    private var userInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.displayName)
                .font(.headline)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

            Text(statusSubtitle)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
    }

    private var messageIcon: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.caption.bold())
            Text(user.friendshipStatus.actionLabel)
                .font(.caption.bold())
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(selectedTheme.colors(for: colorScheme).cardBackground.opacity(1))
            .shadow(
                color: selectedTheme.colors(for: colorScheme).primary[0]
                    .opacity(colorScheme == .dark ? 0.35 : 0.2),
                radius: 16,
                y: 6
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        selectedTheme.colors(for: colorScheme).accent
                            .opacity(colorScheme == .dark ? 0.4 : 0.3),
                        selectedTheme.colors(for: colorScheme).accent.opacity(0.05),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var statusSubtitle: String {
        switch user.friendshipStatus {
        case .none:
            return "Choose a room type, then send a friend request with your first message."
        case .friend:
            return "Choose Regular Room or Chamber of Secrets."
        case .outgoingPending:
            return "Friend request already sent."
        case .incomingPending:
            return "This user already sent you a request."
        }
    }

    private var statusIcon: String {
        switch user.friendshipStatus {
        case .none:
            return "paperplane.fill"
        case .friend:
            return "bubble.left.and.bubble.right.fill"
        case .outgoingPending:
            return "clock.fill"
        case .incomingPending:
            return "person.badge.plus"
        }
    }

    private var statusColor: Color {
        switch user.friendshipStatus {
        case .none:
            return selectedTheme.colors(for: colorScheme).accent
        case .friend:
            return .green
        case .outgoingPending, .incomingPending:
            return .orange
        }
    }
}

#Preview {
    UsersListView(users: [], selectUser: { _ in })
}
