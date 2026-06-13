import SwiftUI

/// Lists users this account has blocked and lets the user unblock them.
struct BlockedUsersView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    @State private var blocked: [BlockedUser] = []
    @State private var isLoading = true
    @State private var unblocking: Set<String> = []

    private var theme: ThemeColors { selectedTheme.colors(for: colorScheme) }
    private var userId: String { userDefaults.string(forKey: userIdUserDefaultsKey) ?? "" }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .tint(theme.accent)
                    .padding(.top, 80)
            } else if blocked.isEmpty {
                emptyState
            } else {
                VStack(spacing: 12) {
                    ForEach(blocked) { user in
                        row(for: user)
                    }
                }
                .padding(16)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Blocked Users")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.slash")
                .font(.system(size: 44))
                .foregroundStyle(theme.textSecondary)
            Text("No blocked users")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Text("People you block won't be able to message you or send friend requests.")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 80)
    }

    private func row(for user: BlockedUser) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinearGradient(colors: theme.primary, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(user.displayInitial)
                        .font(.headline.bold())
                        .foregroundStyle(theme.text)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            Button {
                Task { await unblock(user) }
            } label: {
                if unblocking.contains(user.id) {
                    ProgressView().tint(theme.accent)
                } else {
                    Text("Unblock")
                        .font(.subheadline.bold())
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(theme.accent.opacity(0.12))
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(unblocking.contains(user.id))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.textSecondary.opacity(0.1), lineWidth: 1)
        )
    }

    private func load() async {
        guard !userId.isEmpty else { isLoading = false; return }
        defer { isLoading = false }
        blocked = (try? await ConvexChatAPI.shared.listBlocked(userId: userId)) ?? []
    }

    private func unblock(_ user: BlockedUser) async {
        unblocking.insert(user.id)
        defer { unblocking.remove(user.id) }
        do {
            try await ConvexChatAPI.shared.unblockUser(userId: userId, targetUserId: user.id)
            blocked.removeAll { $0.id == user.id }
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: "Could not unblock: \(error.localizedDescription)")
        }
    }
}
