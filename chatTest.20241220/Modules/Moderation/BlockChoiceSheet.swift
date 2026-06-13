import SwiftUI

/// Confirmation sheet shown before blocking a user. Surfaces what the two
/// share (group rooms / a DM) and offers to also wipe the direct messages.
struct BlockChoiceSheet: View {
    let targetUserId: String
    let targetName: String
    /// Called after a successful block so the caller can pop/refresh.
    var onBlocked: () -> Void = {}

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var shared: SharedContext?
    @State private var isLoading = true
    @State private var deleteDm = false
    @State private var isBlocking = false

    private var theme: ThemeColors { selectedTheme.colors(for: colorScheme) }
    private var userId: String { userDefaults.string(forKey: userIdUserDefaultsKey) ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Block \(targetName)?")
                            .font(.title3.bold())
                            .foregroundStyle(theme.textPrimary)
                        Text("They won't be able to message you or send friend requests, and any existing friendship will be removed.")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }

                    if isLoading {
                        ProgressView().tint(theme.accent)
                    } else if let shared {
                        if shared.hasDm {
                            Toggle(isOn: $deleteDm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Also delete our direct messages")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(theme.textPrimary)
                                    Text("Removes the conversation for both of you. This can't be undone.")
                                        .font(.caption)
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                            .tint(theme.destructive)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.cardBackground))
                        }

                        if !shared.groupRooms.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("You're both in \(shared.groupRooms.count) group room\(shared.groupRooms.count == 1 ? "" : "s")")
                                    .font(.caption.bold())
                                    .foregroundStyle(theme.textSecondary)
                                Text("Group rooms aren't affected — leave them manually if you wish.")
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.cardBackground))
                        }
                    }

                    Button {
                        Task { await block() }
                    } label: {
                        HStack {
                            if isBlocking { ProgressView().tint(.white) }
                            Text(isBlocking ? "Blocking…" : "Block")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.destructive))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBlocking)
                }
                .padding(20)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Block User")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        defer { isLoading = false }
        guard !userId.isEmpty else { return }
        shared = try? await ConvexChatAPI.shared.listShared(userId: userId, otherUserId: targetUserId)
    }

    private func block() async {
        guard !userId.isEmpty else { return }
        isBlocking = true
        defer { isBlocking = false }
        do {
            try await ConvexChatAPI.shared.blockUser(userId: userId, targetUserId: targetUserId, deleteDm: deleteDm)
            dismiss()
            onBlocked()
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: "Could not block: \(error.localizedDescription)")
        }
    }
}
