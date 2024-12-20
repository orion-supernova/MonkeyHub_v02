//
//  ContentView.swift
//  chatTest.20241220
//
//  Created by muratcankoc on 20/12/2024.
//

import CloudKit
import SwiftUI

struct ContentView: View {
    @StateObject private var cloudKit = CloudKitManager.shared
    @State private var myRooms: [ChatRoom] = []
    @State private var availableRooms: [ChatRoom] = []
    @State private var isShowingNewRoomSheet = false
    @State private var isShowingAvailableRooms = false
    @State private var newRoomName = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var showingSignOutAlert = false

    // MARK: - Room Operations
    private func loadData() async {
        do {
            myRooms = try await cloudKit.fetchChatRooms()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func loadAvailableRooms() async {
        do {
            availableRooms = try await cloudKit.fetchAvailableRooms()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func createRoom() async {
        guard let currentUser = cloudKit.currentUser else { return }

        let room = ChatRoom(
            name: newRoomName,
            createdBy: currentUser.id,
            participants: [currentUser.id]
        )

        do {
            try await cloudKit.createChatRoom(room)
            await loadData()
            isShowingNewRoomSheet = false
            newRoomName = ""
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func joinRoom(_ room: ChatRoom) async {
        do {
            try await cloudKit.joinRoom(room)
            await loadData()
            isShowingAvailableRooms = false
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func leaveRoom(_ room: ChatRoom) async {
        do {
            try await cloudKit.leaveRoom(room)
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section("My Rooms") {
                    if myRooms.isEmpty {
                        ContentUnavailableView(
                            "No Rooms",
                            systemImage: "bubble.left.circle",
                            description: Text(
                                "Create a new room or join an existing one to start chatting")
                        )
                    } else {
                        ForEach(myRooms) { room in
                            NavigationLink(destination: ChatRoomView(room: room)) {
                                RoomListItem(room: room)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task {
                                        await leaveRoom(room)
                                    }
                                } label: {
                                    Label("Leave", systemImage: "door.left.hand.open")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chat Rooms")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isShowingNewRoomSheet = true
                        } label: {
                            Label("New Room", systemImage: "plus")
                        }

                        Button {
                            isShowingAvailableRooms = true
                        } label: {
                            Label("Join Room", systemImage: "person.2")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showingSignOutAlert = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingNewRoomSheet) {
                NavigationView {
                    Form {
                        TextField("Room Name", text: $newRoomName)
                    }
                    .navigationTitle("New Room")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isShowingNewRoomSheet = false
                                newRoomName = ""
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create") {
                                Task {
                                    await createRoom()
                                }
                            }
                            .disabled(
                                newRoomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingAvailableRooms) {
                NavigationView {
                    List {
                        if availableRooms.isEmpty {
                            ContentUnavailableView(
                                "No Rooms Available",
                                systemImage: "bubble.left.circle",
                                description: Text(
                                    "There are no rooms available to join at the moment")
                            )
                        } else {
                            ForEach(availableRooms) { room in
                                RoomListItem(room: room)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        Task {
                                            await joinRoom(room)
                                        }
                                    }
                            }
                        }
                    }
                    .navigationTitle("Available Rooms")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                isShowingAvailableRooms = false
                            }
                        }
                    }
                }
                .task {
                    await loadAvailableRooms()
                }
            }
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {
                    showingError = false
                }
            } message: {
                Text(errorMessage)
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
    }

    private func signOut() async {
        cloudKit.currentUser = nil
    }
}

struct RoomListItem: View {
    let room: ChatRoom

    var body: some View {
        VStack(alignment: .leading) {
            Text(room.name)
                .font(.headline)
            if let lastMessage = room.lastMessage {
                Text(lastMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    ContentView()
}
