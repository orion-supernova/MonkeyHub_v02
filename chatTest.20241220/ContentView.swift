//
//  ContentView.swift
//  chatTest.20241220
//
//  Created by muratcankoc on 20/12/2024.
//

import CloudKit
import SwiftUI

struct ContentView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @StateObject private var cloudKit = CloudKitManager.shared
    @State private var myRooms: [ChatRoom] = []
    @State private var isShowingNewRoomSheet = false
    @State private var newRoomName = ""
    @State private var showingSignOutAlert = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isShowingJoinRoomSheet = false
    @State private var availableRooms: [ChatRoom] = []
    @State private var isShowingFindFriendSheet = false
    @State private var isShowingSearchView = false

    // MARK: - Room Operations
    private func loadData() async {
        do {
            myRooms = try await cloudKit.fetchChatRooms()
        } catch let error {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private func createRoom(type: RoomType, messageLifetime: TimeInterval?) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let room = ChatRoom(
            name: newRoomName,
            createdBy: userId,
            participants: [userId],
            type: type,
            messageLifetime: messageLifetime
        )

        do {
            try await cloudKit.createChatRoom(room)
            await loadData()
            isShowingNewRoomSheet = false
            newRoomName = ""
        } catch let error {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private func leaveRoom(_ room: ChatRoom) async {
        do {
            try await cloudKit.leaveRoom(room)
            await loadData()
        } catch let error {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad or large screen: 3 columns
            return [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ]
        } else {
            // iPhone: 2 columns
            return [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ]
        }
    }

    private var headerHeight: CGFloat {
        switch verticalSizeClass {
        case .compact:
            return 200  // Landscape mode
        default:
            return 260  // Portrait mode
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Header background that covers status bar and header content
                LinearGradient(
                    colors: selectedTheme.colors(for: colorScheme).headerBackground,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .frame(height: headerHeight)

                ScrollView {
                    VStack(spacing: 0) {
                        // Header content
                        VStack(spacing: verticalSizeClass == .compact ? 12 : 20) {
                            // Status bar spacing
                            Color.clear
                                .frame(height: verticalSizeClass == .compact ? 20 : 50)

                            // Title and action buttons
                            VStack(spacing: 16) {
                                // Title and room count
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Chat Rooms")
                                            .font(
                                                .system(
                                                    size: verticalSizeClass == .compact ? 28 : 34,
                                                    weight: .bold
                                                )
                                            )
                                            .foregroundStyle(
                                                selectedTheme.colors(for: colorScheme).text)

                                        Text(
                                            "\(myRooms.count) Active Room\(myRooms.count == 1 ? "" : "s")"
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).text.opacity(0.8)
                                        )
                                    }

                                    Spacer()
                                }

                                // Action buttons
                                HStack(spacing: 12) {
                                    // Create Room button
                                    Button {
                                        isShowingNewRoomSheet = true
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "plus.circle.fill")
                                            Text("New Room")
                                        }
                                        .font(.headline)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).text
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            LinearGradient(
                                                colors: [
                                                    selectedTheme.colors(for: colorScheme)
                                                        .headerOverlay,
                                                    selectedTheme.colors(for: colorScheme)
                                                        .headerOverlay.opacity(0.8),
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    selectedTheme.colors(for: colorScheme).text
                                                        .opacity(0.2),
                                                    lineWidth: 1
                                                )
                                        )
                                    }

                                    // Search button
                                    Button {
                                        isShowingSearchView = true
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "magnifyingglass")
                                            Text("Search")
                                        }
                                        .font(.headline)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).text
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            LinearGradient(
                                                colors: [
                                                    selectedTheme.colors(for: colorScheme)
                                                        .headerOverlay,
                                                    selectedTheme.colors(for: colorScheme)
                                                        .headerOverlay.opacity(0.8),
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    selectedTheme.colors(for: colorScheme).text
                                                        .opacity(0.2),
                                                    lineWidth: 1
                                                )
                                        )
                                    }
                                }
                                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 24)
                            }
                            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 24)
                            .padding(.bottom, verticalSizeClass == .compact ? 16 : 24)

                            // Rooms list
                            LazyVStack(spacing: 16) {
                                if myRooms.isEmpty {
                                    VStack(spacing: 16) {
                                        Image(systemName: "bubble.left.circle.fill")
                                            .font(.system(size: 60))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: selectedTheme.colors(for: colorScheme)
                                                        .primary,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .padding(.bottom, 8)

                                        Text("No Active Rooms")
                                            .font(.title2.bold())
                                            .foregroundStyle(
                                                selectedTheme.colors(for: colorScheme).textPrimary)

                                        Text("Create a new room to start chatting")
                                            .font(.subheadline)
                                            .foregroundStyle(
                                                selectedTheme.colors(for: colorScheme).textSecondary
                                            )
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(40)
                                } else {
                                    VStack(spacing: 24) {
                                        // Section header
                                        HStack {
                                            Text("Your Rooms")
                                                .font(.title2.bold())
                                                .foregroundStyle(
                                                    selectedTheme.colors(for: colorScheme)
                                                        .textPrimary)

                                            Spacer()

                                            Text("\(myRooms.count) Total")
                                                .font(.subheadline)
                                                .foregroundStyle(
                                                    selectedTheme.colors(for: colorScheme)
                                                        .textSecondary
                                                )
                                        }
                                        .padding(
                                            .horizontal, horizontalSizeClass == .regular ? 32 : 20)

                                        // Rooms grid
                                        LazyVGrid(columns: gridColumns, spacing: 16) {
                                            ForEach(myRooms) { room in
                                                NavigationLink(
                                                    destination: ChatRoomView(room: room)
                                                ) {
                                                    EnhancedRoomCard(room: room) {
                                                        Task {
                                                            await leaveRoom(room)
                                                        }
                                                    }
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(
                                            .horizontal, horizontalSizeClass == .regular ? 32 : 16)
                                    }
                                }
                            }
                            .padding(.top, 16)
                            .background(
                                ZStack {
                                    // Main background with shadow
                                    RoundedRectangle(cornerRadius: 32)
                                        .fill(selectedTheme.colors(for: colorScheme).background)
                                        .shadow(
                                            color: selectedTheme.colors(for: colorScheme).primary[0]
                                                .opacity(0.1),
                                            radius: 20,
                                            y: -10
                                        )

                                    // Extended top edge overlay
                                    Rectangle()
                                        .fill(selectedTheme.colors(for: colorScheme).background)
                                        .frame(height: 50)  // Increased height
                                        .offset(y: -25)  // Adjusted offset
                                }
                            )
                            .offset(y: -40)  // Increased overlap with header
                            .padding(.top, 40)  // Adjusted padding to compensate
                        }
                    }
                }
            }
            .background(selectedTheme.colors(for: colorScheme).background)
            .sheet(isPresented: $isShowingNewRoomSheet) {
                EnhancedNewRoomSheet(
                    isShowingSheet: $isShowingNewRoomSheet,
                    roomName: $newRoomName,
                    createRoom: createRoom
                )
            }
            .sheet(isPresented: $isShowingJoinRoomSheet) {
                JoinRoomSheet(
                    isShowingSheet: $isShowingJoinRoomSheet,
                    availableRooms: availableRooms,
                    joinRoom: { room in
                        Task {
                            await joinRoom(room)
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingFindFriendSheet) {
                FindFriendSheet(
                    isShowingSheet: $isShowingFindFriendSheet,
                    createPrivateRoom: { friend in
                        Task {
                            await createPrivateRoom(with: friend)
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingSearchView) {
                SearchView()
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    await signOut()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    private func isUserExistOnDatabase() -> Bool {
        // Get the user ID from UserDefaults
        guard let userId = userDefaults.string(forKey: userIdUserDefaultsKey) else {
            // If no user ID is stored in UserDefaults, return false
            return false
        }

        // Reference to the CloudKit database
        let database = cloudKit.database

        // Create a predicate to search for the user by their ID
        let predicate = NSPredicate(format: "id == %@", userId)
        let query = CKQuery(recordType: "ChatUser", predicate: predicate)

        // Perform the query asynchronously
        let semaphore = DispatchSemaphore(value: 0)
        var userExists = false

        database.fetch(withQuery: query) { result in
            switch result {
            case .success(let matchResults):
                let results = matchResults.matchResults
                guard !results.isEmpty else {
                    userExists = false
                    semaphore.signal()
                    return
                }
                userExists = true
            case .failure(let error):
                print(error.localizedDescription)
                userExists = false
            }
            // Signal semaphore to continue execution
            semaphore.signal()
        }
        // Wait for the async CloudKit query to finish
        semaphore.wait()

        return userExists
    }

    private func signOut() async {
        userDefaults.set(nil, forKey: userIdUserDefaultsKey)
        cloudKit.isAuthenticated = false
    }

    private func themeIcon(for theme: AppTheme) -> String {
        switch theme {
        case .basic:
            return "circle.grid.cross.fill"
        case .cyberpunk:
            return "bolt.circle.fill"
        case .retroWave:
            return "sunset.fill"
        case .neonNight:
            return "sparkles"
        case .deepOcean:
            return "water.waves"
        }
    }

    private func joinRoom(_ room: ChatRoom) async {
        do {
            try await cloudKit.joinRoom(room)
            await loadData()
            isShowingJoinRoomSheet = false
        } catch let error {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private func loadAvailableRooms() async {
        do {
            availableRooms = try await cloudKit.fetchAvailableRooms()
        } catch let error {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private func createPrivateRoom(with friend: ChatUser) async {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let room = ChatRoom(
            name: "Chat with \(friend.name)",
            createdBy: userId,
            participants: [userId, friend.id],
            type: .regular,
            messageLifetime: nil
        )

        do {
            try await cloudKit.createChatRoom(room)
            await loadData()
            isShowingFindFriendSheet = false
        } catch let error {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }
}

struct EnhancedRoomCard: View {
    let room: ChatRoom
    let action: () -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with room avatar and leave button
            HStack {
                // Room avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text(room.name.prefix(1).uppercased())
                        .font(.title3.bold())
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                }
                .frame(width: 44, height: 44)
                .shadow(
                    color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3),
                    radius: 5, y: 2)

                Spacer()

                // Leave button
                Button(action: action) {
                    Image(systemName: "door.left.hand.open")
                        .font(.headline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).destructive)
                        .frame(width: 32, height: 32)
                        .background(selectedTheme.colors(for: colorScheme).destructive.opacity(0.1))
                        .clipShape(Circle())
                }
            }

            // Room info
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    .lineLimit(1)

                if let lastMessage = room.lastMessage {
                    Text(lastMessage)
                        .font(.caption)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .imageScale(.small)
                    Text("\(room.participants.count)")
                }
                .font(.caption2)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedTheme.colors(for: colorScheme).cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(
            color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.1), radius: 8, y: 4
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    selectedTheme.colors(for: colorScheme).accent.opacity(0.1), lineWidth: 1)
        )
    }
}

struct EnhancedNewRoomSheet: View {
    @Binding var isShowingSheet: Bool
    @Binding var roomName: String
    @State private var selectedType: RoomType = .regular
    @State private var messageLifetime: TimeInterval = 300  // 5 minutes default
    let createRoom: (RoomType, TimeInterval?) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @State private var animateContent = false
    @State private var selectedOptionId: TimeInterval?
    @Namespace private var animation
    @FocusState private var isRoomNameFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollID = UUID()  // For scroll anchor
    @Environment(\.colorScheme) private var colorScheme

    private let lifetimeOptions: [(String, TimeInterval)] = [
        ("5 minutes", 300),
        ("1 hour", 3600),
        ("24 hours", 86400),
        ("7 days", 604800),
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Enhanced Header with animation
                    VStack(spacing: 8) {
                        Text("Create New Room")
                            .font(.title.bold())
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                            .opacity(animateContent ? 1 : 0)
                            .offset(y: animateContent ? 0 : 20)

                        Text("Select room type and customize settings")
                            .font(.subheadline)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                            .opacity(animateContent ? 1 : 0)
                            .offset(y: animateContent ? 0 : 20)
                    }
                    .padding(.top, 24)

                    // Room Type Selector with improved animations
                    VStack(alignment: .leading, spacing: 20) {
                        Text("ROOM TYPE")
                            .font(.caption.bold())
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                            .padding(.leading, 4)
                            .opacity(animateContent ? 1 : 0)
                            .offset(y: animateContent ? 0 : 20)

                        VStack(spacing: 16) {
                            ForEach([RoomType.regular, .secret], id: \.self) { type in
                                Button {
                                    withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                                        selectedType = type
                                    }
                                } label: {
                                    HStack(spacing: 16) {
                                        // Room type icon
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: selectedType == type
                                                            ? selectedTheme.colors(for: colorScheme)
                                                                .primary
                                                            : [
                                                                selectedTheme.colors(
                                                                    for: colorScheme
                                                                ).cardBackground
                                                            ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 44, height: 44)
                                                .shadow(
                                                    color: selectedType == type
                                                        ? selectedTheme.colors(for: colorScheme)
                                                            .primary[0].opacity(
                                                                0.3)
                                                        : .clear,
                                                    radius: 5, y: 2
                                                )

                                            Image(
                                                systemName: type == .regular
                                                    ? "bubble.left.circle.fill" : "lock.shield.fill"
                                            )
                                            .font(.title3)
                                            .foregroundStyle(
                                                selectedType == type
                                                    ? selectedTheme.colors(for: colorScheme).text
                                                    : selectedTheme.colors(for: colorScheme)
                                                        .textSecondary
                                            )
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(
                                                type == .regular
                                                    ? "Regular Room" : "Chamber of Secrets"
                                            )
                                            .font(.headline)
                                            .foregroundStyle(
                                                selectedTheme.colors(for: colorScheme).textPrimary)

                                            Text(
                                                type == .regular
                                                    ? "Standard chat room with permanent messages"
                                                    : "Secret room with self-destructing messages"
                                            )
                                            .font(.caption)
                                            .foregroundStyle(
                                                selectedTheme.colors(for: colorScheme).textSecondary
                                            )
                                            .lineLimit(2)
                                        }

                                        Spacer()

                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(
                                                selectedTheme.colors(for: colorScheme).accent
                                            )
                                            .opacity(selectedType == type ? 1 : 0)
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(
                                                selectedTheme.colors(for: colorScheme)
                                                    .cardBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(
                                                selectedType == type
                                                    ? selectedTheme.colors(for: colorScheme).accent
                                                    : selectedTheme.colors(for: colorScheme)
                                                        .textSecondary.opacity(
                                                            0.1),
                                                lineWidth: selectedType == type ? 1.5 : 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .opacity(animateContent ? 1 : 0)
                                .offset(y: animateContent ? 0 : 20)
                            }
                        }
                    }

                    // Message Lifetime Selector with improved animations
                    if selectedType == .secret {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MESSAGE LIFETIME")
                                .font(.caption.bold())
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).textSecondary
                                )
                                .padding(.leading, 4)
                                .transition(.move(edge: .top).combined(with: .opacity))

                            VStack(spacing: 12) {
                                ForEach(lifetimeOptions, id: \.1) { option in
                                    Button {
                                        withAnimation(.spring(duration: 0.3)) {
                                            messageLifetime = option.1
                                            selectedOptionId = option.1
                                        }
                                    } label: {
                                        HStack {
                                            Text(option.0)
                                                .font(.subheadline)
                                                .foregroundStyle(
                                                    selectedTheme.colors(for: colorScheme)
                                                        .textPrimary)

                                            Spacer()

                                            if messageLifetime == option.1 {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(
                                                        selectedTheme.colors(for: colorScheme)
                                                            .accent
                                                    )
                                                    .matchedGeometryEffect(
                                                        id: "check\(option.1)",
                                                        in: animation
                                                    )
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(
                                                    selectedTheme.colors(for: colorScheme)
                                                        .cardBackground
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(
                                                            messageLifetime == option.1
                                                                ? selectedTheme.colors(
                                                                    for: colorScheme
                                                                ).accent
                                                                : selectedTheme.colors(
                                                                    for: colorScheme
                                                                ).textSecondary
                                                                    .opacity(0.1),
                                                            lineWidth: messageLifetime == option.1
                                                                ? 1.5 : 1
                                                        )
                                                )
                                        )
                                        .scaleEffect(messageLifetime == option.1 ? 1.02 : 1)
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Room name input with simplified keyboard handling
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ROOM NAME")
                            .font(.caption.bold())
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                            .padding(.leading, 4)
                            .opacity(animateContent ? 1 : 0)
                            .offset(y: animateContent ? 0 : 20)

                        TextField("Enter room name", text: $roomName)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(selectedTheme.colors(for: colorScheme).cardBackground)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        roomName.isEmpty
                                            ? selectedTheme.colors(for: colorScheme).textSecondary
                                                .opacity(0.1)
                                            : selectedTheme.colors(for: colorScheme).accent.opacity(
                                                0.2),
                                        lineWidth: 1
                                    )
                            )
                            .focused($isRoomNameFocused)
                    }
                    .id(scrollID)  // Add scroll anchor
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)

                    // Create button with enhanced animation
                    Button {
                        // Add haptic feedback
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()

                        Task {
                            await createRoom(
                                selectedType,
                                selectedType == .secret ? messageLifetime : nil
                            )
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(
                                systemName: selectedType == .regular
                                    ? "plus.circle.fill" : "lock.shield.fill"
                            )
                            .transition(.scale.combined(with: .opacity))

                            Text("Create \(selectedType == .regular ? "Room" : "Secret Room")")
                        }
                        .font(.headline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(
                            color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3),
                            radius: 5, y: 2
                        )
                        .scaleEffect(roomName.isEmpty ? 0.98 : 1)
                    }
                    .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                }
                .padding(24)
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 20 : 16)
            }
            .onChange(of: isRoomNameFocused) { _, isFocused in
                if isFocused {
                    withAnimation {
                        proxy.scrollTo(scrollID, anchor: .bottom)
                    }
                }
            }
            .background(selectedTheme.colors(for: colorScheme).background)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isRoomNameFocused = false
                        }
                    }
                    .foregroundStyle(
                        colorScheme == .dark
                            ? selectedTheme.colors(for: colorScheme).accent
                            : selectedTheme.colors(for: colorScheme).primary[0]
                    )
                }

                // Add close button
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingSheet = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    animateContent = true
                }
            }
            .onChange(of: selectedType) { _, _ in
                let impactLight = UIImpactFeedbackGenerator(style: .light)
                impactLight.impactOccurred()
            }
        }
        .presentationDetents([
            .height(selectedType == .secret ? 720 : 580),
            .large,
        ])
        .presentationDragIndicator(.visible)
        .presentationBackground(selectedTheme.colors(for: colorScheme).background)
        .interactiveDismissDisabled()
    }
}

struct JoinRoomSheet: View {
    @Binding var isShowingSheet: Bool
    let availableRooms: [ChatRoom]
    let joinRoom: (ChatRoom) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Join Room")
                    .font(.title.bold())
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                Text("Join an existing room")
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }

            if availableRooms.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("No Rooms Available")
                        .font(.title2.bold())
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                    Text("Create a new room or try again later")
                        .font(.subheadline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(availableRooms) { room in
                            Button {
                                Task {
                                    await joinRoom(room)
                                }
                            } label: {
                                HStack(spacing: 16) {
                                    // Room icon
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: selectedTheme.colors(for: colorScheme)
                                                        .primary,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )

                                        Image(
                                            systemName: room.type == .regular
                                                ? "bubble.left" : "lock.shield"
                                        )
                                        .font(.title3.bold())
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).text)
                                    }
                                    .frame(width: 44, height: 44)

                                    // Room info
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(room.name)
                                            .font(.headline)
                                            .foregroundStyle(
                                                selectedTheme.colors(for: colorScheme).textPrimary)

                                        HStack {
                                            Image(systemName: "person.2.fill")
                                                .imageScale(.small)
                                            Text("\(room.participants.count) members")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.headline)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).textSecondary)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(
                                            selectedTheme.colors(for: colorScheme).accent.opacity(
                                                0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, 24)
        .background(selectedTheme.colors(for: colorScheme).background)
    }
}

#Preview {
    ContentView()
}
