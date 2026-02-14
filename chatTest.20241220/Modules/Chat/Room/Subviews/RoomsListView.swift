import SwiftUI
import CloudKit

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
        .onChange(of: room.avatarAsset) { _ in
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

        // Fallback: fetch from CloudKit if local file not available
        Task {
            await fetchAvatarFromCloud()
        }
    }

    private func fetchAvatarFromCloud() async {
        do {
            // Query by the "id" field, not recordID (they may differ)
            let predicate = NSPredicate(format: "%K == %@", ChatRoom.idKey, room.id)
            let query = CKQuery(recordType: ChatRoom.recordType, predicate: predicate)

            let (records, _) = try await CloudKitManager.shared.database.records(matching: query, resultsLimit: 1)
            guard let record = try records.first?.1.get() else { return }

            if let asset = record[ChatRoom.avatarAssetKey] as? CKAsset,
               let fileURL = asset.fileURL,
               let data = try? Data(contentsOf: fileURL),
               let image = PlatformImage.fromData(data) {
                await MainActor.run {
                    avatarImage = image
                }
            }
        } catch {
            // Silently fail - will show placeholder
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

            HStack {
                Image(systemName: "person.2.fill")
                    .imageScale(.small)
                Text("\(room.participants.count) members")
            }
            .font(.caption)
            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
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