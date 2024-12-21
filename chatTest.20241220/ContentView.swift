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

    // MARK: - Room Operations
    private func loadData() async {
        do {
            myRooms = try await cloudKit.fetchChatRooms()
        } catch let error {
            AlertManager.shared.showAlert(title: "Error", message: error.localizedDescription)
        }
    }

    private func createRoom() async {
        //        guard let currentUser = cloudKit.currentUser else { return }
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        let room = ChatRoom(
            name: newRoomName,
            createdBy: userId,
            participants: [userId]
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
                    colors: selectedTheme.colors.headerBackground,
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

                            // Title and menu
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Chat Rooms")
                                        .font(
                                            .system(
                                                size: verticalSizeClass == .compact ? 28 : 34,
                                                weight: .bold
                                            )
                                        )
                                        .foregroundStyle(selectedTheme.colors.text)

                                    Text(
                                        "\(myRooms.count) Active Room\(myRooms.count == 1 ? "" : "s")"
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(selectedTheme.colors.text.opacity(0.8))
                                }

                                Spacer()

                                // Menu button
                                Menu {
                                    // Theme selector with icons
                                    Menu {
                                        ForEach(AppTheme.allCases, id: \.self) { theme in
                                            Button {
                                                withAnimation(.spring(duration: 0.4)) {
                                                    selectedTheme = theme
                                                }
                                            } label: {
                                                HStack {
                                                    Image(systemName: themeIcon(for: theme))
                                                    Text(theme.rawValue)
                                                    if selectedTheme == theme {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        Label("Theme", systemImage: "paintpalette.fill")
                                    }

                                    Button {
                                        isShowingNewRoomSheet = true
                                    } label: {
                                        Label("New Room", systemImage: "plus.circle.fill")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        showingSignOutAlert = true
                                    } label: {
                                        Label(
                                            "Sign Out",
                                            systemImage: "rectangle.portrait.and.arrow.right")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle.fill")
                                        .font(.title)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(selectedTheme.colors.text)
                                }
                            }

                            // Create Room button
                            Button {
                                isShowingNewRoomSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                    Text("Create New Room")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(selectedTheme.colors.text)
                                .frame(maxWidth: horizontalSizeClass == .regular ? 400 : .infinity)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            selectedTheme.colors.headerOverlay,
                                            selectedTheme.colors.headerOverlay.opacity(0.8),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            selectedTheme.colors.text.opacity(0.2), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 5, y: 2)
                            }
                            .frame(maxWidth: .infinity)
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
                                                colors: selectedTheme.colors.primary,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .padding(.bottom, 8)

                                    Text("No Active Rooms")
                                        .font(.title2.bold())
                                        .foregroundStyle(selectedTheme.colors.textPrimary)

                                    Text("Create a new room to start chatting")
                                        .font(.subheadline)
                                        .foregroundStyle(selectedTheme.colors.textSecondary)
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
                                            .foregroundStyle(selectedTheme.colors.textPrimary)

                                        Spacer()

                                        Text("\(myRooms.count) Total")
                                            .font(.subheadline)
                                            .foregroundStyle(selectedTheme.colors.textSecondary)
                                    }
                                    .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 20)

                                    // Rooms grid
                                    LazyVGrid(columns: gridColumns, spacing: 16) {
                                        ForEach(myRooms) { room in
                                            NavigationLink(destination: ChatRoomView(room: room)) {
                                                EnhancedRoomCard(room: room) {
                                                    Task {
                                                        await leaveRoom(room)
                                                    }
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
                                }
                            }
                        }
                        .padding(.top, 16)
                        .background(
                            ZStack {
                                // Main background with shadow
                                RoundedRectangle(cornerRadius: 32)
                                    .fill(selectedTheme.colors.background)
                                    .shadow(
                                        color: selectedTheme.colors.primary[0].opacity(0.1),
                                        radius: 20,
                                        y: -10
                                    )

                                // Extended top edge overlay
                                Rectangle()
                                    .fill(selectedTheme.colors.background)
                                    .frame(height: 50)  // Increased height
                                    .offset(y: -25)  // Adjusted offset
                            }
                        )
                        .offset(y: -40)  // Increased overlap with header
                        .padding(.top, 40)  // Adjusted padding to compensate
                    }
                }
            }
            .background(selectedTheme.colors.background)
            .sheet(isPresented: $isShowingNewRoomSheet) {
                EnhancedNewRoomSheet(
                    isShowingSheet: $isShowingNewRoomSheet,
                    roomName: $newRoomName,
                    createRoom: createRoom
                )
                .presentationDetents([.height(300)])
                .presentationBackground(selectedTheme.colors.background)
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
}

struct EnhancedRoomCard: View {
    let room: ChatRoom
    let action: () -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with room avatar and leave button
            HStack {
                // Room avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: selectedTheme.colors.primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text(room.name.prefix(1).uppercased())
                        .font(.title3.bold())
                        .foregroundStyle(selectedTheme.colors.text)
                }
                .frame(width: 44, height: 44)
                .shadow(color: selectedTheme.colors.primary[0].opacity(0.3), radius: 5, y: 2)

                Spacer()

                // Leave button
                Button(action: action) {
                    Image(systemName: "door.left.hand.open")
                        .font(.headline)
                        .foregroundStyle(selectedTheme.colors.destructive)
                        .frame(width: 32, height: 32)
                        .background(selectedTheme.colors.destructive.opacity(0.1))
                        .clipShape(Circle())
                }
            }

            // Room info
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors.textPrimary)
                    .lineLimit(1)

                if let lastMessage = room.lastMessage {
                    Text(lastMessage)
                        .font(.caption)
                        .foregroundStyle(selectedTheme.colors.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .imageScale(.small)
                    Text("\(room.participants.count)")
                }
                .font(.caption2)
                .foregroundStyle(selectedTheme.colors.accent)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedTheme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: selectedTheme.colors.primary[0].opacity(0.1), radius: 8, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(selectedTheme.colors.accent.opacity(0.1), lineWidth: 1)
        )
    }
}

struct EnhancedNewRoomSheet: View {
    @Binding var isShowingSheet: Bool
    @Binding var roomName: String
    let createRoom: () async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic

    var body: some View {
        VStack(spacing: 24) {
            // Enhanced header
            VStack(spacing: 8) {
                Text("Create New Room")
                    .font(.title.bold())
                    .foregroundStyle(selectedTheme.colors.textPrimary)

                Text("Start a new conversation")
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors.textSecondary)
            }

            // Enhanced room name input
            VStack(alignment: .leading, spacing: 8) {
                Text("ROOM NAME")
                    .font(.caption.bold())
                    .foregroundStyle(selectedTheme.colors.textSecondary)
                    .padding(.leading, 4)

                TextField("Enter room name", text: $roomName)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(selectedTheme.colors.cardBackground)
                    .foregroundStyle(selectedTheme.colors.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selectedTheme.colors.accent.opacity(0.2), lineWidth: 1)
                    )
            }

            // Enhanced create button
            Button {
                Task {
                    await createRoom()
                }
            } label: {
                Text("Create Room")
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors.text)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: selectedTheme.colors.primary,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: selectedTheme.colors.primary[0].opacity(0.3), radius: 5, y: 2)
            }
            .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding(24)
        .background(selectedTheme.colors.background)
    }
}

#Preview {
    ContentView()
}
