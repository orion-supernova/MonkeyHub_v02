import SwiftUI

struct ChatRoomGridView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let rooms: [ChatRoom]
    let isLoading: Bool
    let unreadCounts: [String: Int]
    let typingTextProvider: (String) -> String?
    let selectedRoomIndex: Int?
    let onLeaveRoom: (ChatRoom) -> Void

    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        } else {
            [GridItem(.flexible()), GridItem(.flexible())]
        }
    }

    var body: some View {
        if rooms.isEmpty {
            ChatRoomEmptyView(isLoading: isLoading)
        } else {
            RoomGridContent(
                rooms: rooms,
                gridColumns: gridColumns,
                unreadCounts: unreadCounts,
                typingTextProvider: typingTextProvider,
                selectedRoomIndex: selectedRoomIndex,
                onLeaveRoom: onLeaveRoom
            )
        }
    }
}

// MARK: - Empty / Loading State

private struct ChatRoomEmptyView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var emptyIconSize: Double = 60

    let isLoading: Bool

    var body: some View {
        if isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Loading Rooms...")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(40)
        } else {
            ContentUnavailableView {
                Label("No Active Rooms", systemImage: "bubble.left.circle.fill")
                    .foregroundStyle(
                        LinearGradient(
                            colors: selectedTheme.colors(for: colorScheme).primary,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            } description: {
                Text("Create a new room to start chatting")
            }
            .frame(maxWidth: .infinity)
            .padding(40)
        }
    }
}

// MARK: - Room Grid Content

private struct RoomGridContent: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let rooms: [ChatRoom]
    let gridColumns: [GridItem]
    let unreadCounts: [String: Int]
    let typingTextProvider: (String) -> String?
    let selectedRoomIndex: Int?
    let onLeaveRoom: (ChatRoom) -> Void

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Your Rooms")
                    .font(.title2.bold())
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                Spacer()

                Text("\(rooms.count) Total")
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 20)

            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(rooms.enumerated(), id: \.element.id) { index, room in
                    NavigationLink(value: room) {
                        EnhancedRoomCard(
                            room: room,
                            unreadCount: unreadCounts[room.id] ?? 0,
                            typingText: typingTextProvider(room.id),
                            isSelected: selectedRoomIndex == index
                        ) {
                            onLeaveRoom(room)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
        }
    }
}
