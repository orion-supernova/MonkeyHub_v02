import CloudKit
import SwiftUI

struct FindFriendSheet: View {
    @Binding var isShowingSheet: Bool
    let createPrivateRoom: (ChatUser) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchText = ""
    @State private var users: [ChatUser] = []
    @State private var isSearching = false
    @State private var animateContent = false
    @State private var errorMessage: String?
    @State private var showError = false

    var filteredUsers: [ChatUser] {
        if searchText.isEmpty {
            return users
        }
        return users.filter { user in
            user.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Header background
                LinearGradient(
                    colors: selectedTheme.colors(for: colorScheme).headerBackground,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .frame(height: 140)

                ScrollView {
                    VStack(spacing: 0) {
                        // Header content
                        VStack(spacing: 20) {
                            // Status bar spacing
                            Color.clear
                                .frame(height: 50)

                            // Search bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .font(.title3)
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)

                                TextField("Search by username", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                            }
                            .padding()
                            .background(selectedTheme.colors(for: colorScheme).headerOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(
                                        selectedTheme.colors(for: colorScheme).text.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 24)
                        .padding(.bottom, 24)

                        // Users list with rounded top corners
                        LazyVStack(spacing: 16) {
                            if filteredUsers.isEmpty {
                                EmptyStateView(searchText: searchText)
                                    .opacity(animateContent ? 1 : 0)
                                    .offset(y: animateContent ? 0 : 20)
                            } else {
                                ForEach(filteredUsers) { user in
                                    UserRowView(
                                        user: user,
                                        action: {
                                            Task {
                                                await handleUserSelection(user)
                                            }
                                        }
                                    )
                                    .opacity(animateContent ? 1 : 0)
                                    .offset(y: animateContent ? 0 : 20)
                                }
                            }
                        }
                        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
                        .padding(.top, 16)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 32)
                                    .fill(selectedTheme.colors(for: colorScheme).background)
                                    .shadow(
                                        color: selectedTheme.colors(for: colorScheme).primary[0]
                                            .opacity(0.1),
                                        radius: 20,
                                        y: -10
                                    )

                                // Top edge overlay
                                Rectangle()
                                    .fill(selectedTheme.colors(for: colorScheme).background)
                                    .frame(height: 50)
                                    .offset(y: -25)
                            }
                        )
                        .offset(y: -40)
                        .padding(.top, 40)
                    }
                }
                .refreshable {
                    await loadUsers()
                }
            }
            .background(selectedTheme.colors(for: colorScheme).background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingSheet = false
                    }
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                }
            }
            .alert(
                "Error", isPresented: $showError,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text(errorMessage ?? "An error occurred")
                })
        }
        .task {
            await loadUsers()
            withAnimation(.easeOut(duration: 0.4)) {
                animateContent = true
            }
        }
    }

    private func loadUsers() async {
        isSearching = true
        defer { isSearching = false }

        do {
            users = try await CloudKitManager.shared.fetchUsers()
        } catch {
            errorMessage = "Failed to load users: \(error.localizedDescription)"
            showError = true
        }
    }

    private func handleUserSelection(_ user: ChatUser) async {
        do {
            await createPrivateRoom(user)
        } catch {
            errorMessage = "Failed to create chat: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Supporting Views
private struct EmptyStateView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    let searchText: String

    var body: some View {
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

            Text(searchText.isEmpty ? "No Users Found" : "No Matching Users")
                .font(.title2.bold())
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

            Text(
                searchText.isEmpty
                    ? "Try searching for users" : "Try a different search"
            )
            .font(.subheadline)
            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

private struct UserRowView: View {
    let user: ChatUser
    let action: () -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // User avatar
                Circle()
                    .fill(
                        LinearGradient(
                            colors: selectedTheme.colors(for: colorScheme).primary,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(user.name.prefix(1).uppercased())
                            .font(.title3.bold())
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.headline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                    Text("Tap to start chatting")
                        .font(.caption)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }

                Spacer()

                Image(systemName: "message.circle.fill")
                    .font(.title3)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedTheme.colors(for: colorScheme).cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        selectedTheme.colors(for: colorScheme).accent.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
