import SwiftUI

struct NewChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NewChatViewModel()
    @State private var roomName = ""
    @State private var selectedUsers: Set<ChatUser> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Room Name", text: $roomName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Chat Details")
                }

                Section {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if viewModel.users.isEmpty {
                        ContentUnavailableView(
                            "No Users Found",
                            systemImage: "person.slash",
                            description: Text("Try again later")
                        )
                    } else {
                        ForEach(viewModel.users) { user in
                            UserSelectionRow(
                                user: user,
                                isSelected: selectedUsers.contains(user)
                            ) {
                                if selectedUsers.contains(user) {
                                    selectedUsers.remove(user)
                                } else {
                                    selectedUsers.insert(user)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Select Participants")
                } footer: {
                    Text("Select at least one participant")
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        Task {
                            await createRoom()
                        }
                    }
                    .bold()
                    .disabled(roomName.isEmpty || selectedUsers.isEmpty)
                }
            }
            .overlay {
                if viewModel.isCreating {
                    ProgressView("Creating chat room...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .task {
            await viewModel.fetchUsers()
        }
    }

    private func createRoom() async {
        do {
            try await viewModel.createRoom(
                name: roomName,
                participants: Array(selectedUsers)
            )
            dismiss()
        } catch {
            // Error handling is done in ViewModel
        }
    }
}

private struct UserSelectionRow: View {
    let user: ChatUser
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                // User Avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(user.name.prefix(1).uppercased())
                            .font(.headline)
                            .foregroundColor(Color.accentColor)
                    }

                VStack(alignment: .leading) {
                    Text(user.name)
                        .font(.headline)

                    Text(user.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.accentColor)
                }
            }
        }
        .foregroundColor(.primary)
    }
}
