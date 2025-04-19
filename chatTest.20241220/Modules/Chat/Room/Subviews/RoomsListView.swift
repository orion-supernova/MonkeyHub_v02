import SwiftUI

struct RoomsListView: View {
    let rooms: [ChatRoom]
    let joinRoom: (ChatRoom) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            if rooms.isEmpty {
                emptyStateView
            } else {
                ForEach(rooms) { room in
                    RoomRow(room: room, joinRoom: joinRoom)
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
    let joinRoom: (ChatRoom) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            Task {
                await joinRoom(room)
            }
        } label: {
            HStack(spacing: 16) {
                roomIcon
                roomInfo
                Spacer()
                joinButton
            }
            .padding()
            .background(cardBackground)
            .overlay(cardBorder)
        }
        .buttonStyle(.plain)
    }

    private var roomIcon: some View {
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

    private var joinButton: some View {
        Text("Join")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
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
    RoomsListView(rooms: [], joinRoom: { _ in })
}
