import SwiftUI

struct ChatRoomList: View {
    @StateObject private var viewModel = ChatRoomListViewModel()
    @State private var showNewChatSheet = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ChatRoomListContent(
                viewModel: viewModel,
                searchText: $searchText,
                showNewChatSheet: $showNewChatSheet
            )
        }
    }
}

// MARK: - Content View
private struct ChatRoomListContent: View {
    @ObservedObject var viewModel: ChatRoomListViewModel
    @Binding var searchText: String
    @Binding var showNewChatSheet: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if viewModel.rooms.isEmpty {
                    EmptyStateView()
                } else {
                    ForEach(viewModel.filteredRooms) { room in
                        ChatRoomCard(room: room)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal)
        }
        .refreshable {
            await viewModel.fetchRooms()
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer,
            prompt: "Search chats..."
        )
        .onChange(of: searchText) { _ in
            viewModel.filterRooms(searchText)
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewChatSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showNewChatSheet) {
            NewChatSheet()
        }
    }
}

// MARK: - Chat Room Card
private struct ChatRoomCard: View {
    let room: ChatRoom

    var body: some View {
        NavigationLink(destination: ChatRoomView(room: room)) {
            HStack {
                // Room Avatar
                RoomAvatar(name: room.name)

                // Room Info
                RoomInfo(room: room)

                Spacer()

                // Time and Badge
                TimeAndBadge(room: room)
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }
}

// MARK: - Supporting Views
private struct RoomAvatar: View {
    let name: String

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: 50, height: 50)
            .overlay {
                Text(name.prefix(1).uppercased())
                    .font(.title2.bold())
                    .foregroundColor(Color.accentColor)
            }
    }
}

private struct RoomInfo: View {
    let room: ChatRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(room.name)
                .font(.headline)
                .foregroundColor(.primary)

            Text(room.lastMessage ?? "No messages yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

private struct TimeAndBadge: View {
    let room: ChatRoom

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let date = room.lastMessageDate {
                Text(date, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Chats Yet")
                .font(.title2.bold())
                .foregroundColor(.primary)

            Text("Start a new conversation or join an existing chat room")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

#Preview {
    ChatRoomListContent(viewModel: ChatRoomListViewModel(),
                        searchText: .constant(""),
                        showNewChatSheet: .constant(true))
}
