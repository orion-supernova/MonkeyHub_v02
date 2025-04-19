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
    }

    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(user.name.prefix(1).uppercased())
                .font(.title3.bold())
                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
        }
        .frame(width: 44, height: 44)
    }

    private var userInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.name)
                .font(.headline)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

            Text("Tap to start chatting")
                .font(.caption)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
        }
    }

    private var messageIcon: some View {
        Image(systemName: "message.circle.fill")
            .font(.title3)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        selectedTheme.colors(for: colorScheme).accent,
                        selectedTheme.colors(for: colorScheme).accent.opacity(0.8),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(
                color: selectedTheme.colors(for: colorScheme).accent.opacity(0.3),
                radius: 4,
                y: 2
            )
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
}

#Preview {
    UsersListView(users: [], selectUser: { _ in })
}
