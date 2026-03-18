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
        HStack(spacing: 14) {
            HStack(spacing: 16) {
                roomIcon
                roomInfo
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(primaryInteractionGesture)

            VStack(alignment: .trailing, spacing: 10) {
                joinStatusButton

                Button {
                    showRoomInfo?(room)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Details")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(selectedTheme.colors(for: colorScheme).background.opacity(0.92))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.16),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 90, maxHeight: 90)
        .background(cardBackground)
        .overlay(cardBorder)
        .opacity(isJoined ? 0.62 : 1)
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
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.25), lineWidth: 1)
                        )

                    Image(systemName: room.type == .regular ? "bubble.left" : "lock.shield")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                }
                .frame(width: 50, height: 50)
            }
        }
        .shadow(
            color: selectedTheme.colors(for: colorScheme).primary[0].opacity(colorScheme == .dark ? 0.24 : 0.16),
            radius: 10,
            y: 5
        )
    }

    private var roomInfo: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(room.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 7) {
                roomMetaChip(
                    systemImage: "person.2.fill",
                    title: memberCountText,
                    tint: selectedTheme.colors(for: colorScheme).textSecondary,
                    fill: selectedTheme.colors(for: colorScheme).headerOverlay.opacity(0.55)
                )
                if room.type == .secret {
                    roomMetaChip(
                        systemImage: "flame.fill",
                        title: "Secret",
                        tint: .orange,
                        fill: Color.orange.opacity(0.14)
                    )
                }

                if room.hasPassword {
                    roomMetaChip(
                        systemImage: "lock.fill",
                        title: "Password",
                        tint: .blue,
                        fill: Color.blue.opacity(0.12)
                    )
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
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Already a member")
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(selectedTheme.colors(for: colorScheme).headerOverlay.opacity(0.65))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.12), lineWidth: 1)
                )
            } else {
                HStack(spacing: 5) {
                    Image(systemName: room.hasPassword ? "key.fill" : "arrow.right.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(room.hasPassword ? "Unlock" : "Join")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    selectedTheme.colors(for: colorScheme).headerOverlay.opacity(0.9),
                                    selectedTheme.colors(for: colorScheme).cardBackground.opacity(0.98),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            room.hasPassword
                                ? Color.blue.opacity(0.22)
                                : selectedTheme.colors(for: colorScheme).accent.opacity(0.18),
                            lineWidth: 1
                        )
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(
                LinearGradient(
                    colors: [
                        selectedTheme.colors(for: colorScheme).cardBackground.opacity(isJoined ? 0.88 : 1),
                        selectedTheme.colors(for: colorScheme).background.opacity(isJoined ? 0.9 : 0.98),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, y: 3)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.3),
                        selectedTheme.colors(for: colorScheme).textSecondary.opacity(isJoined ? 0.06 : 0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    @ViewBuilder
    private func roomMetaChip(systemImage: String, title: String, tint: Color, fill: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(fill)
        )
        .overlay(
            Capsule()
                .strokeBorder(tint.opacity(0.12), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

#Preview {
    RoomsListView(rooms: [], joinedRoomIds: [], joinRoom: { _ in }, openRoom: { _ in }, showRoomInfo: { _ in })
}
