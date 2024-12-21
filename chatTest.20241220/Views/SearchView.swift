import CloudKit
import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchMode: SearchMode = .rooms
    @State private var searchText = ""
    @State private var users: [ChatUser] = []
    @State private var rooms: [ChatRoom] = []
    @State private var isSearching = false
    @State private var animateContent = false
    @State private var errorMessage: String?
    @State private var showError = false

    enum SearchMode: String, CaseIterable {
        case rooms = "Rooms"
        case friends = "Friends"

        var icon: String {
            switch self {
            case .rooms: return "bubble.left.and.bubble.right.fill"
            case .friends: return "person.2.fill"
            }
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
                .frame(height: 180)

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

                                TextField(
                                    searchMode == .rooms ? "Search rooms" : "Search users",
                                    text: $searchText
                                )
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

                            // Mode selector
                            HStack(spacing: 0) {
                                ForEach(SearchMode.allCases, id: \.self) { mode in
                                    Button {
                                        withAnimation(.spring(duration: 0.3)) {
                                            searchMode = mode
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: mode.icon)
                                            Text(mode.rawValue)
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(
                                            searchMode == mode
                                                ? selectedTheme.colors(for: colorScheme).text
                                                : selectedTheme.colors(for: colorScheme).text
                                                    .opacity(0.6)
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            searchMode == mode
                                                ? selectedTheme.colors(for: colorScheme)
                                                    .headerOverlay : Color.clear
                                        )
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(4)
                            .background(
                                selectedTheme.colors(for: colorScheme).headerOverlay.opacity(0.5)
                            )
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 24)
                        .padding(.bottom, 24)

                        // Results list
                        Group {
                            if searchMode == .rooms {
                                RoomsListView(rooms: rooms, joinRoom: { _ in })
                            } else {
                                UsersListView(users: users, selectUser: { _ in })
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
            }
            .background(selectedTheme.colors(for: colorScheme).background)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                }
            }
        }
    }
}

// Add RoomsListView and UsersListView similar to previous implementations

private struct RoomsListView: View {
    let rooms: [ChatRoom]
    let joinRoom: (ChatRoom) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            if rooms.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("No Rooms Found")
                        .font(.title2.bold())
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                    Text("Try searching with different keywords")
                        .font(.subheadline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                ForEach(rooms) { room in
                    Button {
                        Task {
                            await joinRoom(room)
                        }
                    } label: {
                        HStack(spacing: 16) {
                            // Room icon
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: selectedTheme.colors(for: colorScheme).primary,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                Image(
                                    systemName: room.type == .regular
                                        ? "bubble.left" : "lock.shield"
                                )
                                .font(.title3.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(room.name)
                                    .font(.headline)
                                    .foregroundStyle(
                                        selectedTheme.colors(for: colorScheme).textPrimary)

                                HStack {
                                    Image(systemName: "person.2.fill")
                                        .imageScale(.small)
                                    Text("\(room.participants.count) members")
                                }
                                .font(.caption)
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).textSecondary)
                            }

                            Spacer()

                            Text("Join")
                                .font(.subheadline.weight(.semibold))
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
        }
    }
}

private struct UsersListView: View {
    let users: [ChatUser]
    let selectUser: (ChatUser) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            if users.isEmpty {
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
            } else {
                ForEach(users) { user in
                    Button {
                        Task {
                            await selectUser(user)
                        }
                    } label: {
                        HStack(spacing: 16) {
                            // User avatar
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

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.headline)
                                    .foregroundStyle(
                                        selectedTheme.colors(for: colorScheme).textPrimary)

                                Text("Tap to start chatting")
                                    .font(.caption)
                                    .foregroundStyle(
                                        selectedTheme.colors(for: colorScheme).textSecondary
                                    )
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
        }
    }
}

#Preview {
    SearchView()
}
