import SwiftUI

struct RoomsListView: View {
    let rooms: [ChatRoom]
    let joinedRoomIds: Set<String>
    let joinRoom: (ChatRoom) async -> Void
    var openRoom: ((ChatRoom) -> Void)? = nil
    var showRoomInfo: ((ChatRoom) -> Void)? = nil
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
                        openRoom: openRoom,
                        showRoomInfo: showRoomInfo
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
    var showRoomInfo: ((ChatRoom) -> Void)? = nil
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @State private var avatarImage: PlatformImage?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 16) {
                roomIcon
                roomInfo
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(primaryInteractionGesture)

            VStack(spacing: 8) {
                joinStatusButton

                Button {
                    showRoomInfo?(room)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }
        }
        .padding()
        .frame(minHeight: 82, maxHeight: 82)
        .background(cardBackground)
        .overlay(cardBorder)
        .opacity(isJoined ? 0.55 : 1)
        .onAppear {
            loadAvatar()
        }
        .onChange(of: room.avatarStorageId) { _ in
            loadAvatar()
        }
    }

    private var primaryInteractionGesture: some Gesture {
        TapGesture()
            .exclusively(before: DragGesture(minimumDistance: 10))
            .onEnded { value in
                guard case .first = value else { return }
                if isJoined {
                    openRoom?(room)
                } else {
                    Task {
                        await joinRoom(room)
                    }
                }
            }
    }

    private func loadAvatar() {
        avatarImage = nil

        if let avatarURL = room.avatarURL,
           let image = PlatformImage.fromFile(avatarURL.path) {
            avatarImage = image
            return
        }

        if let storageId = room.avatarStorageId {
            Task {
                avatarImage = await ConvexFileCacheService.shared.image(for: storageId)
            }
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
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .imageScale(.small)
                    Text(memberCountText)
                }
                .font(.caption)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                .fixedSize(horizontal: true, vertical: false)

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
                    .fixedSize(horizontal: true, vertical: false)
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
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .lineLimit(1)
        }
    }

    private var memberCountText: String {
        let count = room.resolvedMemberCount
        return "\(count) member" + (count == 1 ? "" : "s")
    }

    private var joinStatusButton: some View {
        Group {
            if isJoined {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Already a member")
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            } else {
                Text("Join")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(selectedTheme.colors(for: colorScheme).cardBackground.opacity(isJoined ? 0.82 : 1))
            .shadow(
                color: selectedTheme.colors(for: colorScheme).primary[0]
                    .opacity(isJoined ? 0.08 : (colorScheme == .dark ? 0.35 : 0.2)),
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
                            .opacity(isJoined ? 0.12 : (colorScheme == .dark ? 0.4 : 0.3)),
                        selectedTheme.colors(for: colorScheme).accent.opacity(isJoined ? 0.02 : 0.05),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

#Preview {
    RoomsListView(rooms: [], joinedRoomIds: [], joinRoom: { _ in }, openRoom: { _ in }, showRoomInfo: { _ in })
}
