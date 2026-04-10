import SwiftUI

struct ChatListContentView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ObservedObject var viewModel: ChatListViewModel
    let selectedSection: ChatListViewModel.Section
    let selectedRoomIndex: Int?
    let onLeaveRoom: (ChatRoom) -> Void
    let onStartFriendChat: (ChatUser) -> Void
    let onPreviewRequest: (FriendRequest) -> Void
    let onOpenOutgoingRequest: (FriendRequest) -> Void

    private var headerHeight: CGFloat {
        verticalSizeClass == .compact ? 240 : 320
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if selectedSection == .chats {
                    ChatRoomGridView(
                        rooms: viewModel.myRooms,
                        isLoading: viewModel.isLoading,
                        unreadCounts: viewModel.unreadCounts,
                        typingTextProvider: viewModel.typingText,
                        selectedRoomIndex: selectedRoomIndex,
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
            .padding(.top, 16)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                    .fill(selectedTheme.colors(for: colorScheme).background)
                    .shadow(
                        color: selectedTheme.colors(for: colorScheme).primary[0]
                            .opacity(0.1),
                        radius: 20,
                        y: -10
                    )
                    .padding(.bottom, -1000)
            )
        }
        .padding(.top, headerHeight - 20)
        .scrollClipDisabled()
    }
}
