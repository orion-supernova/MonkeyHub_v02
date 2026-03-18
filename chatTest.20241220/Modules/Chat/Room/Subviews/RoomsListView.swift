import SwiftUI

struct RoomsListView: View {
    let rooms: [ChatRoom]
    let joinedRoomIds: Set<String>
    let joinRoom: (ChatRoom) async -> Void
    var openRoom: ((ChatRoom) -> Void)? = nil
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            if rooms.isEmpty {
                emptyStateView
            } else {
                ForEach(rooms) { room in
                    RoomRow(
                        room: room,
                        isJoined: joinedRoomIds.contains(room.id),
                        joinRoom: joinRoom,
                        openRoom: openRoom
                    )
                }
            }
        }
    }

    private var emptyStateView: some View {
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
    }
}

private struct RoomRow: View {
    let room: ChatRoom
    let isJoined: Bool
    let joinRoom: (ChatRoom) async -> Void
    var openRoom: ((ChatRoom) -> Void)? = nil
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @State private var avatarImage: PlatformImage?

    var body: some View {
        Button {
            if isJoined {
                // Already joined - open the room directly
                openRoom?(room)
            } else {
                // Not joined - join first
                Task {
                    await joinRoom(room)
                }
            }
        } label: {
            HStack(spacing: 16) {
                roomIcon
                roomInfo
                Spacer()
                joinStatusButton
            }
            .padding()
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
        .onAppear {
            loadAvatar()
        }
        .onChange(of: room.avatarStorageId) { _ in
            loadAvatar()
        }
    }

    private func loadAvatar() {
        // Try persisted avatarURL first (resolving filename to current session's path)
        if let avatarURL = room.avatarURL {
            let filename = avatarURL.lastPathComponent
            if let resolvedURL = AssetPersistenceService.shared.getURL(for: filename),
               let data = try? Data(contentsOf: resolvedURL),
               let image = PlatformImage.fromData(data) {
                avatarImage = image
                return
            }
        }

        // Fallback: fetch from Convex storage if available
        if let storageId = room.avatarStorageId {
            Task { await fetchAvatarFromConvex(storageId: storageId) }
        }
    }

    private func fetchAvatarFromConvex(storageId: String) async {
        do {
            if let urlString = try await ConvexChatAPI.shared.getFileURL(storageId: storageId),
               let url = URL(string: urlString) {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = PlatformImage.fromData(data) {
                    await MainActor.run { avatarImage = image }
                }
            }
        } catch {
            // Silently fail — show placeholder
        }
    }

    private var roomIcon: some View {
        Group {
            if let avatarImage = avatarImage {
                Image(platformImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: room.type == .regular ? "bubble.left" : "lock.shield")
                        .font(.title3.bold())
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                }
                .frame(width: 44, height: 44)
            }
        }
    }

    private var roomInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(room.name)
                .font(.headline)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

            HStack(spacing: 6) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .imageScale(.small)
                    Text("\(room.participants.count) members")
                }
                .font(.caption)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)

                if room.type == .secret {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                        Text("Secret")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.2), Color.red.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5))
                }

                if room.hasPassword {
                    HStack(spacing: 2) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text("Password")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.2), Color.blue.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(Capsule().strokeBorder(Color.indigo.opacity(0.3), lineWidth: 0.5))
                }
            }
        }
    }

    private var joinStatusButton: some View {
        Group {
            if isJoined {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Joined")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            } else {
                Text("Join")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
            }
        }
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
    RoomsListView(rooms: [], joinedRoomIds: [], joinRoom: { _ in }, openRoom: { _ in })
}