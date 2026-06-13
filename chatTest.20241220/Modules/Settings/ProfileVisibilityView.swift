import SwiftUI

/// Per-field privacy controls (avatar, status, last seen, read receipts, and
/// whether others may send friend requests). Backed by `users:updateVisibility`.
struct ProfileVisibilityView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var visibility = ProfileVisibility.default
    @State private var isLoading = true
    @State private var isSaving = false

    private var theme: ThemeColors { selectedTheme.colors(for: colorScheme) }
    private var userId: String { userDefaults.string(forKey: userIdUserDefaultsKey) ?? "" }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                if isLoading {
                    ProgressView()
                        .tint(theme.accent)
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 16) {
                        levelPicker(
                            title: "Profile Photo",
                            icon: "person.crop.circle",
                            selection: $visibility.avatar
                        )
                        levelPicker(
                            title: "Online Status",
                            icon: "circle.fill",
                            selection: $visibility.status
                        )
                        levelPicker(
                            title: "Last Seen",
                            icon: "clock",
                            selection: $visibility.lastSeen
                        )
                        levelPicker(
                            title: "Read Receipts",
                            icon: "checkmark.circle",
                            selection: $visibility.seen,
                            footnote: "Who can see when you've read their messages."
                        )

                        toggleRow(
                            title: "Allow Friend Requests",
                            icon: "person.badge.plus",
                            isOn: $visibility.acceptsFriendRequests
                        )
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Privacy")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .onChange(of: visibility) { _ in
            // Persist on every change; the backend merges field-by-field.
            Task { await save() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(theme.accent)
            Text("Control who can see your details")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    private func levelPicker(
        title: String,
        icon: String,
        selection: Binding<VisibilityLevel>,
        footnote: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(theme.accent)
                    .frame(width: 28)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
            }

            Picker(title, selection: selection) {
                ForEach(VisibilityLevel.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isSaving)

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.textSecondary.opacity(0.1), lineWidth: 1)
        )
    }

    private func toggleRow(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(theme.accent)
                .frame(width: 28)
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
            }
            .tint(theme.accent)
            .disabled(isSaving)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.textSecondary.opacity(0.1), lineWidth: 1)
        )
    }

    private func load() async {
        guard !userId.isEmpty else { isLoading = false; return }
        defer { isLoading = false }
        if let user = try? await ConvexChatAPI.shared.fetchOwnProfile(userId: userId),
           let vis = user.visibility {
            visibility = vis
        }
    }

    private func save() async {
        guard !userId.isEmpty, !isLoading else { return }
        isSaving = true
        defer { isSaving = false }
        try? await ConvexChatAPI.shared.updateVisibility(
            userId: userId,
            avatar: visibility.avatar,
            status: visibility.status,
            lastSeen: visibility.lastSeen,
            seen: visibility.seen,
            acceptsFriendRequests: visibility.acceptsFriendRequests
        )
    }
}
