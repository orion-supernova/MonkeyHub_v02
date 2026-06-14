import SwiftUI

struct ChatListContentView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var viewModel: ChatListViewModel
    let selectedSection: ChatListViewModel.Section
    let selectedRoomIndex: Int?
    let onOpenRoom: (ChatRoom) -> Void
    let onLeaveRoom: (ChatRoom) -> Void
    let onStartFriendChat: (ChatUser) -> Void
    let onPreviewRequest: (FriendRequest) -> Void
    let onOpenOutgoingRequest: (FriendRequest) -> Void

    // Just the scrollable rows — the enclosing RoomsSheet owns the (UIKit) ScrollView and chrome.
    // Non-lazy: lazy stacks misalign when hosted in a UIKit UIScrollView (no SwiftUI scroll viewport).
    var body: some View {
        VStack(spacing: 16) {
                if selectedSection == .chats {
                    ChatRoomGridView(
                        rooms: viewModel.myRooms,
                        isLoading: viewModel.isLoading,
                        unreadCounts: viewModel.unreadCounts,
                        typingTextProvider: viewModel.typingText,
                        selectedRoomIndex: selectedRoomIndex,
                        onOpenRoom: onOpenRoom,
                        onLeaveRoom: onLeaveRoom
                    )
                } else {
                    ConnectionsPanelView(
                        friends: viewModel.friends,
                        incomingRequests: viewModel.incomingRequests,
                        outgoingRequests: viewModel.outgoingRequests,
                        selectedSection: selectedSection,
                        startFriendChat: onStartFriendChat,
                        removeFriend: { friend in
                            Task { await viewModel.removeFriend(friend) }
                        },
                        approveRequest: { request in
                            Task { await viewModel.approve(request) }
                        },
                        rejectRequest: { request in
                            Task { await viewModel.reject(request) }
                        },
                        cancelRequest: { request in
                            Task { await viewModel.cancelRequest(request) }
                        },
                        previewRequest: onPreviewRequest,
                        openOutgoingRequest: onOpenOutgoingRequest
                    )
                }

                Color.clear
                    .frame(height: 100)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
    }
}
