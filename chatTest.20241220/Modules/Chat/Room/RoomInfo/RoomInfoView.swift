import SwiftUI
import CloudKit

struct RoomInfoView: View {
    @StateObject private var viewModel: RoomInfoViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @State private var showImagePicker = false
    @State private var selectedImage: PlatformImage?
    @State private var roomAvatarImage: PlatformImage?
    @State private var showVisibilityAlert = false
    @State private var pendingVisibilityValue: Bool = false
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var isEditingDescription = false
    @State private var editedDescription = ""
    
    private let currentUserId: String
    private let isCreator: Bool
    
    init(room: ChatRoom) {
        self._viewModel = StateObject(wrappedValue: RoomInfoViewModel(room: room))
        self.currentUserId = UserDefaults.standard.string(forKey: "userId") ?? ""
        self.isCreator = room.createdBy == currentUserId
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    avatarSection
                    roomInfoSection
                    membersSection
                    
                    if isCreator {
                        actionsSection
                    }
                }
                .padding()
            }
            .background(selectedTheme.colors(for: colorScheme).background)
            .navigationTitle("Room Info")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: {
                    #if canImport(UIKit)
                    return .navigationBarTrailing
                    #else
                    return .automatic
                    #endif
                }()) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                }
            }
            .task {
                await viewModel.refreshRoom()
                await viewModel.loadMembers()
                loadRoomAvatar()
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { newImage in
                if let image = newImage {
                    Task {
                        await viewModel.updateRoomAvatar(image)
                        roomAvatarImage = image
                        selectedImage = nil
                    }
                }
            }
            .alert("Change Room Visibility", isPresented: $showVisibilityAlert) {
                Button("Cancel", role: .cancel) {}
                Button(pendingVisibilityValue ? "Make Private" : "Make Public") {
                    Task {
                        await viewModel.updateRoomPrivacy(pendingVisibilityValue)
                    }
                }
            } message: {
                Text(pendingVisibilityValue 
                    ? "This will make the room private. Only members can see and join this room." 
                    : "This will make the room public. Anyone can search and join this room.")
            }
        }
    }
    
    private func loadRoomAvatar() {
        guard let avatarAsset = viewModel.room.avatarAsset,
              let fileURL = avatarAsset.fileURL else { return }
        
        if let data = try? Data(contentsOf: fileURL),
           let image = PlatformImage.fromData(data) {
            roomAvatarImage = image
        }
    }
    
    private var avatarSection: some View {
        VStack(spacing: 12) {
            Button {
                showImagePicker = true
            } label: {
                ZStack {
                    if let avatarImage = roomAvatarImage {
                        Image(platformImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: selectedTheme.colors(for: colorScheme).primary,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .overlay(
                                Text(String(viewModel.room.name.prefix(2)).uppercased())
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                            )
                    }
                    
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "camera.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .background(
                                    Circle()
                                        .fill(selectedTheme.colors(for: colorScheme).accent)
                                        .frame(width: 32, height: 32)
                                )
                                .offset(x: -8, y: -8)
                        }
                    }
                    .frame(width: 120, height: 120)
                }
            }
            
            if isEditingName {
                HStack {
                    TextField("Room Name", text: $editedName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                    
                    Button {
                        Task {
                            await viewModel.updateRoomName(editedName)
                            isEditingName = false
                        }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                    }
                    
                    Button {
                        isEditingName = false
                        editedName = viewModel.room.name
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    }
                }
                .padding(.horizontal)
            } else {
                HStack {
                    Text(viewModel.room.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    
                    Button {
                        editedName = viewModel.room.name
                        isEditingName = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                    }
                }
            }
            
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                Text("\(viewModel.room.participants.count) members")
                    .font(.subheadline)
            }
            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
        }
    }
    
    private var roomInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Description", systemImage: "text.alignleft")
                        .font(.headline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    
                    Spacer()
                    
                    if !isEditingDescription {
                        Button {
                            editedDescription = viewModel.room.description ?? ""
                            isEditingDescription = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                        }
                    }
                }
                
                if isEditingDescription {
                    VStack(spacing: 8) {
                        TextEditor(text: $editedDescription)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(selectedTheme.colors(for: colorScheme).background)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedTheme.colors(for: colorScheme).accent.opacity(0.3), lineWidth: 1)
                            )
                        
                        HStack {
                            Button {
                                isEditingDescription = false
                                editedDescription = viewModel.room.description ?? ""
                            } label: {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                            }
                            
                            Spacer()
                            
                            Button {
                                Task {
                                    await viewModel.updateRoomDescription(editedDescription)
                                    isEditingDescription = false
                                }
                            } label: {
                                Text("Save")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                            }
                        }
                    }
                } else {
                    if let description = viewModel.room.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    } else {
                        Text("No description")
                            .font(.body)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.5))
                            .italic()
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedTheme.colors(for: colorScheme).cardBackground)
            .cornerRadius(12)
            
            HStack {
                Label("Type", systemImage: "shield.fill")
                    .font(.subheadline)
                Spacer()
                Text(viewModel.room.type.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }
            .padding()
            .background(selectedTheme.colors(for: colorScheme).cardBackground)
            .cornerRadius(12)
            
            HStack {
                Label("Visibility", systemImage: (viewModel.room.isPrivate ?? true) ? "lock.fill" : "globe")
                    .font(.subheadline)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Text((viewModel.room.isPrivate ?? true) ? "Private" : "Public")
                        .font(.subheadline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    
                    Button {
                        pendingVisibilityValue = !(viewModel.room.isPrivate ?? true)
                        showVisibilityAlert = true
                    } label: {
                        Text((viewModel.room.isPrivate ?? true) ? "Make Public" : "Make Private")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedTheme.colors(for: colorScheme).accent.opacity(0.1))
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(selectedTheme.colors(for: colorScheme).cardBackground)
            .cornerRadius(12)
            
            HStack {
                Label("Created", systemImage: "calendar")
                    .font(.subheadline)
                Spacer()
                Text(viewModel.room.createdAt, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }
            .padding()
            .background(selectedTheme.colors(for: colorScheme).cardBackground)
            .cornerRadius(12)
        }
    }
    
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Members")
                .font(.headline)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                .padding(.horizontal)
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.members.isEmpty {
                Text("No members found")
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.members) { member in
                        MemberRowView(
                            member: member,
                            isCreator: member.id == viewModel.room.createdBy,
                            isCurrentUser: member.id == currentUserId,
                            canRemove: isCreator && member.id != currentUserId,
                            onRemove: {
                                Task {
                                    await viewModel.removeMember(member.id)
                                }
                            }
                        )
                        
                        if member.id != viewModel.members.last?.id {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
                .background(selectedTheme.colors(for: colorScheme).cardBackground)
                .cornerRadius(12)
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(role: .destructive) {
                // TODO: Add delete room functionality
            } label: {
                Label("Delete Room", systemImage: "trash.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedTheme.colors(for: colorScheme).destructive.opacity(0.1))
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).destructive)
                    .cornerRadius(12)
            }
        }
    }
}

struct MemberRowView: View {
    let member: ChatUser
    let isCreator: Bool
    let isCurrentUser: Bool
    let canRemove: Bool
    let onRemove: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @State private var avatarImage: PlatformImage?
    
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let avatarImage = avatarImage {
                    Image(platformImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(member.name.prefix(1)).uppercased())
                                .font(.headline)
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                        )
                }
            }
            .onAppear {
                loadAvatar()
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    
                    if isCreator {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                    }
                    
                    if isCurrentUser {
                        Text("(You)")
                            .font(.caption)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                    }
                }
                
                if !member.username.isEmpty {
                    Text("@\(member.username)")
                        .font(.caption)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }
                
                if !member.email.isEmpty {
                    Text(member.email)
                        .font(.caption2)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.8))
                }
            }
            
            Spacer()
            
            if canRemove {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).destructive)
                }
            }
        }
        .padding()
    }
    
    private func loadAvatar() {
        guard let avatarAsset = member.avatarAsset,
              let fileURL = avatarAsset.fileURL else { 
            return 
        }
        
        if let data = try? Data(contentsOf: fileURL),
           let image = PlatformImage.fromData(data) {
            avatarImage = image
        }
    }
}