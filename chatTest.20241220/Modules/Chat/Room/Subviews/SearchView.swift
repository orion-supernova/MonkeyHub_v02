import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var viewModel = SearchViewModel()
    @State private var animateContent = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Header background with increased height for mode selector
                LinearGradient(
                    colors: selectedTheme.colors(for: colorScheme).headerBackground,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .frame(height: 200)

                ScrollView {
                    VStack(spacing: 0) {
                        // Header content
                        headerContent

                        // Results list with improved visual separation
                        resultsContainer
                    }
                }
            }
            .background(selectedTheme.colors(for: colorScheme).background)
            .navigationTitle("Search")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if canImport(UIKit)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                    #if os(macOS)
                    .buttonStyle(.plain)
                    .focusable(false)
                    #endif
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 600)
        #endif
    }

    private var headerContent: some View {
        VStack(spacing: 20) {
            // Status bar spacing
            Color.clear
                .frame(height: 50)

            // Search bar
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).text)

                    TextField(
                        viewModel.searchMode == .rooms ? "Search rooms" : "Search users",
                        text: $viewModel.searchText
                    )
                    .textFieldStyle(.plain)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                    .submitLabel(.search)
                    .onSubmit {
                        Task {
                            await viewModel.search()
                        }
                    }

                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).text.opacity(0.6))
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        .focusable(false)
                        #endif
                        .contentShape(Circle())
                    }

                    if viewModel.isSearching {
                        ProgressView()
                            .padding(.leading, 5)
                    }
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

                // Error message with improved styling
                errorMessageView
            }

            // Mode selector
            modeSelectorView
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 24)
        .padding(.bottom, 32)
    }

    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage = viewModel.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)

                Text(errorMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                Spacer()

                Button {
                    withAnimation {
                        viewModel.clearErrorMessage()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                    .opacity(0.95)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        selectedTheme.colors(for: colorScheme).accent.opacity(0.3), lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var modeSelectorView: some View {
        HStack(spacing: 0) {
            ForEach(SearchViewModel.SearchMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        viewModel.setSearchMode(mode)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.icon)
                        Text(mode.rawValue)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        viewModel.searchMode == mode
                            ? selectedTheme.colors(for: colorScheme).text
                            : selectedTheme.colors(for: colorScheme).text.opacity(0.6)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        viewModel.searchMode == mode
                            ? selectedTheme.colors(for: colorScheme).headerOverlay
                            : Color.clear
                    )
                    .clipShape(Capsule())
                }
                #if os(macOS)
                .buttonStyle(.plain)
                .focusable(false)
                #endif
                .contentShape(Capsule())
            }
        }
        .padding(4)
        .background(selectedTheme.colors(for: colorScheme).headerOverlay.opacity(0.5))
        .clipShape(Capsule())
    }

    private var resultsContainer: some View {
        Group {
            VStack(spacing: 16) {
                // Results header
                if !viewModel.searchText.isEmpty {
                    HStack {
                        Text(viewModel.searchMode == .rooms ? "Available Rooms" : "Found Users")
                            .font(.headline)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                        Spacer()

                        Text(
                            "\(viewModel.searchMode == .rooms ? viewModel.rooms.count : viewModel.users.count) found"
                        )
                        .font(.subheadline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    }
                    .padding(.horizontal)
                }

                if viewModel.isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if viewModel.searchText.isEmpty {
                    ContentUnavailableView(
                        "Search \(viewModel.searchMode == .rooms ? "Rooms" : "Users")",
                        systemImage: viewModel.searchMode == .rooms
                            ? "bubble.left.and.bubble.right" : "person.2",
                        description: Text(
                            "Enter a search term to find \(viewModel.searchMode == .rooms ? "rooms" : "users")"
                        )
                    )
                    .padding(.top, 40)
                } else if viewModel.searchMode == .rooms && viewModel.rooms.isEmpty
                    || viewModel.searchMode == .users && viewModel.users.isEmpty
                {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Try searching with different keywords")
                    )
                    .padding(.top, 40)
                } else {
                    if viewModel.searchMode == .rooms {
                        RoomsListView(
                            rooms: viewModel.rooms,
                            joinedRoomIds: viewModel.joinedRoomIds,
                            joinRoom: { room in
                                Task {
                                    let userId = UserDefaults.standard.string(forKey: "userId") ?? ""
                                    try? await ConvexChatAPI.shared.joinRoom(roomId: room.id, userId: userId)
                                    var joinedRoom = room
                                    if !joinedRoom.participants.contains(userId) {
                                        joinedRoom.participants.append(userId)
                                    }
                                    dismiss()
                                    // Navigate to the room after joining (pass updated room object)
                                    NavigationStateManager.shared.navigateToRoom(joinedRoom)
                                }
                            },
                            openRoom: { room in
                                // Room is already joined - just navigate to it
                                dismiss()
                                NavigationStateManager.shared.navigateToRoom(room)
                            }
                        )
                    } else {
                        UsersListView(
                            users: viewModel.users,
                            selectUser: { user in
                                Task {
                                    let userId =
                                        UserDefaults.standard.string(forKey: "userId") ?? ""
                                    let roomId = try? await ConvexChatAPI.shared.getOrCreateDM(userId: userId, friendId: user.id)
                                    let room = ChatRoom(
                                        id: roomId ?? UUID().uuidString,
                                        name: "Chat with \(user.displayName)",
                                        createdBy: userId,
                                        participants: [userId, user.id]
                                    )
                                    dismiss()
                                    // Navigate to the newly created room
                                    NavigationStateManager.shared.navigateToRoom(room)
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
        .padding(.top, 24)
        .background(
            ZStack {
                // Main background with enhanced shadow and more contrast
                RoundedRectangle(cornerRadius: 32)
                    .fill(selectedTheme.colors(for: colorScheme).background.opacity(1))
                    .shadow(
                        color: selectedTheme.colors(for: colorScheme).primary[0]
                            .opacity(colorScheme == .dark ? 0.4 : 0.25),
                        radius: 40,
                        y: -20
                    )

                // Improved top edge overlay with gradient
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                selectedTheme.colors(for: colorScheme).background,
                                selectedTheme.colors(for: colorScheme).background,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 80)
                    .offset(y: -40)
            }
        )
        .offset(y: -50)
        .padding(.top, 50)
    }
}

#Preview {
    SearchView()
}
