import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var animateContent = false
    @State private var isShowingThemeSheet = false
    @State private var currentUser: ChatUser?
    @State private var isLoadingUser = true
    @State private var isEditingProfile = false
    @State private var editingName = ""
    @State private var editingUsername = ""
    @State private var editingEmail = ""
    @State private var isImagePickerPresented = false
    @State private var selectedImage: PlatformImage?
    @State private var profileAvatarImage: PlatformImage?
    @State private var isLoadingAvatar = false
    @StateObject private var navigationState = NavigationStateManager.shared
    @State private var showingMigrationSheet = false
    @State private var showingEnvironmentAlert = false
    @State private var showingClearDataAlert = false
    @State private var showingForceReloginAlert = false
    @State private var selectedExportFile: URL?

    private func signOut() async {
        ConvexAuthService.shared.signOut()
    }

    private func forceRelogin() async {
        clearAllLocalData()
        ConvexAuthService.shared.signOut()
        AlertManager.shared.showAlert(
            title: "Success",
            message: "All data cleared. You will be redirected to login."
        )
    }

    private func clearAllLocalData() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("cached_") {
            try? fm.removeItem(at: file)
        }
    }

    private var themeSection: some View {
        SettingsSection(title: "APPEARANCE", padding: 24) {
            VStack(spacing: 16) {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        isShowingThemeSheet = true
                    }
                } label: {
                    ThemeRowContent()
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsRow(
                        icon: "paintbrush.pointed.fill",
                        title: "Appearance & Chat",
                        color: selectedTheme.colors(for: colorScheme).accent
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var developerSection: some View {
        SettingsSection(title: "DEVELOPER TOOLS") {
            VStack(spacing: 16) {
                Button {
                    showingMigrationSheet = true
                } label: {
                    SettingsRow(
                        icon: "arrow.up.arrow.down.circle",
                        title: "Data Migration",
                        color: selectedTheme.colors(for: colorScheme).accent
                    )
                }

                Button {
                    showingClearDataAlert = true
                } label: {
                    SettingsRow(
                        icon: "trash.circle",
                        title: "Clear Local Data",
                        color: selectedTheme.colors(for: colorScheme).destructive
                    )
                }

                Button {
                    showingForceReloginAlert = true
                } label: {
                    SettingsRow(
                        icon: "arrow.clockwise.circle",
                        title: "Force Re-login",
                        color: Color.orange
                    )
                }
            }
        }
    }

    private var accountSection: some View {
        SettingsSection(title: "ACCOUNT") {
            VStack(spacing: 16) {
                SettingsToggleRow(
                    icon: "bell",
                    title: "Notifications",
                    color: selectedTheme.colors(for: colorScheme).accent,
                    isOn: $notificationsEnabled
                )
                .onChange(of: notificationsEnabled) { _, enabled in
                    PushNotificationManager.shared.setNotificationsEnabled(enabled)
                }

                NavigationLink {
                    ProfileVisibilityView()
                } label: {
                    SettingsRow(
                        icon: "lock.fill",
                        title: "Privacy",
                        color: selectedTheme.colors(for: colorScheme).accent
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    BlockedUsersView()
                } label: {
                    SettingsRow(
                        icon: "hand.raised.fill",
                        title: "Blocked Users",
                        color: selectedTheme.colors(for: colorScheme).accent
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showingSignOutAlert = true
                } label: {
                    SettingsRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "Sign Out",
                        color: selectedTheme.colors(for: colorScheme).destructive
                    )
                }

                Button {
                    showingDeleteAccountAlert = true
                } label: {
                    SettingsRow(
                        icon: "trash.fill",
                        title: "Delete Account",
                        color: selectedTheme.colors(for: colorScheme).destructive
                    )
                }
            }
        }
    }

    private func loadCurrentUser() async {
        isLoadingUser = true
        defer { isLoadingUser = false }

        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        guard !userId.isEmpty else { return }

        do {
            currentUser = try await ConvexChatAPI.shared.fetchUser(userId: userId)
        } catch {
            AlertManager.shared.showAlert(
                title: "Error",
                message: "Failed to load user: \(error.localizedDescription)"
            )
        }
    }

    private func loadAvatarIfNeeded() async {
        guard profileAvatarImage == nil,
              let storageId = currentUser?.avatarStorageId else { return }
        isLoadingAvatar = true
        defer { isLoadingAvatar = false }
        if let image = await ConvexFileCacheService.shared.image(for: storageId) {
            profileAvatarImage = image
        } else {
            print("⚠️ SettingsView: could not load avatar for \(storageId)")
        }
    }

    private var profileSection: some View {
        VStack(spacing: 24) {
            ZStack {
                if isLoadingAvatar {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay {
                            ProgressView()
                                .tint(selectedTheme.colors(for: colorScheme).text)
                        }
                } else if let profileAvatarImage = profileAvatarImage {
                    Image(platformImage: profileAvatarImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .shadow(
                            color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3),
                            radius: 10,
                            y: 5
                        )
                } else if isLoadingUser {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay {
                            ProgressView()
                                .tint(selectedTheme.colors(for: colorScheme).text)
                        }
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay {
                            Text((currentUser?.displayInitial) ?? "?")
                                .font(.title.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                        }
                }

                Button {
                    isImagePickerPresented = true
                } label: {
                    Circle()
                        .fill(selectedTheme.colors(for: colorScheme).accent)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.caption.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                        )
                }
                .offset(x: 32, y: 32)
            }

            VStack(spacing: 8) {
                if isEditingProfile {
                    VStack(spacing: 16) {
                        ProfileTextField(
                            title: "Name",
                            text: $editingName,
                            icon: "person.fill"
                        )

                        ProfileTextField(
                            title: "Username",
                            text: $editingUsername,
                            icon: "at"
                        )

                        ProfileTextField(
                            title: "Email",
                            text: $editingEmail,
                            icon: "envelope.fill"
                        )

                        HStack(spacing: 16) {
                            Button(role: .cancel) {
                                isEditingProfile = false
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(
                                        selectedTheme.colors(for: colorScheme).destructive
                                    )
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(
                                                selectedTheme.colors(for: colorScheme)
                                                    .cardBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                selectedTheme.colors(for: colorScheme).destructive
                                                    .opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                Task {
                                    await saveProfileChanges()
                                }
                            } label: {
                                Text("Save")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(
                                                LinearGradient(
                                                    colors: selectedTheme.colors(for: colorScheme)
                                                        .primary,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .shadow(
                                        color: selectedTheme.colors(for: colorScheme).primary[0]
                                            .opacity(0.3),
                                        radius: 8,
                                        y: 4
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    if isLoadingUser {
                        VStack(spacing: 8) {
                            ShimmerView()
                                .frame(width: 150, height: 24)
                            ShimmerView()
                                .frame(width: 120, height: 18)
                            ShimmerView()
                                .frame(width: 180, height: 16)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text(currentUser?.displayName ?? "Unknown")
                                .font(.title2.bold())

                            Text(currentUser.map { "@\($0.username)" } ?? "No username")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let email = currentUser?.email, !email.isEmpty {
                                Text(email)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            startEditing()
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                                .font(.subheadline.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            selectedTheme.colors(for: colorScheme).accent.opacity(
                                                0.2),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(image: $selectedImage)
        }
        .onChange(of: selectedImage) { newImage in
            if let image = newImage {
                Task {
                    await handleImageSelection()
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    let headerHeight = geometry.size.height * 0.4
                    
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).headerBackground,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    .frame(height: headerHeight)

                    ScrollView {
                        VStack(spacing: 0) {
                            profileSection
                                .padding(.top, 40)
                                .padding(.bottom, 32)

                            VStack(spacing: 24) {
                                themeSection
                                developerSection
                                accountSection
                            }
                            .padding(.horizontal, 16)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 32)
                                        .fill(selectedTheme.colors(for: colorScheme).background)
                                        .shadow(
                                            color: selectedTheme.colors(for: colorScheme).primary[0]
                                                .opacity(0.2),
                                            radius: 32,
                                            y: -16
                                        )

                                    VStack(spacing: 0) {
                                        LinearGradient(
                                            colors: [
                                                selectedTheme.colors(for: colorScheme).background,
                                                selectedTheme.colors(for: colorScheme).background
                                                    .opacity(0),
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                        .frame(height: 40)
                                        .offset(y: -20)

                                        Rectangle()
                                            .fill(selectedTheme.colors(for: colorScheme).background)
                                    }
                                    .mask(RoundedRectangle(cornerRadius: 32))
                                }
                            )
                            .mask(RoundedRectangle(cornerRadius: 32))
                            .offset(y: -60)
                            .padding(.top, 60)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(selectedTheme.colors(for: colorScheme).background)
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    Task { await signOut() }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await ConvexAuthService.shared.deleteAccount() }
                }
            } message: {
                Text("This permanently deletes your account, messages, and rooms. This cannot be undone.")
            }
        }
        .onAppear {
            navigationState.currentScreen = .settings
            withAnimation(.easeOut(duration: 0.6)) {
                animateContent = true
            }
        }
        .sheet(isPresented: $isShowingThemeSheet) {
            ThemeSelectionSheet(isShowingSheet: $isShowingThemeSheet)
        }
        .sheet(isPresented: $showingMigrationSheet) {
            DataMigrationSheet(selectedExportFile: $selectedExportFile)
                .interactiveDismissDisabled(true)
        }
        .alert("Clear Local Data", isPresented: $showingClearDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearAllLocalData()
                AlertManager.shared.showAlert(
                    title: "Success",
                    message: "All local data has been cleared. Please restart the app."
                )
            }
        } message: {
            Text("This will delete all cached rooms, messages, and user data from your device. This action cannot be undone.")
        }
        .alert("Force Re-login", isPresented: $showingForceReloginAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Re-login", role: .destructive) {
                Task {
                    await forceRelogin()
                }
            }
        } message: {
            Text("This will clear all local data and authentication state, forcing you to sign in again.")
        }
        .task {
            await loadCurrentUser()
            await loadAvatarIfNeeded()
        }
        .withAlertManager()
    }

    private func startEditing() {
        editingName = currentUser?.displayName ?? ""
        editingUsername = currentUser?.username ?? ""
        editingEmail = currentUser?.email ?? ""
        isEditingProfile = true
    }

    private func saveProfileChanges() async {
        guard let existingUser = currentUser else { return }
        isLoadingUser = true

        do {
            try await ConvexChatAPI.shared.updateUserProfile(
                userId: existingUser.id,
                name: editingName,
                email: editingEmail.isEmpty ? nil : editingEmail,
                bio: existingUser.bio
            )
            isEditingProfile = false
            currentUser = ChatUser(
                id: existingUser.id,
                name: editingName,
                username: editingUsername,
                email: editingEmail,
                avatarStorageId: existingUser.avatarStorageId,
                bio: existingUser.bio
            )
            AlertManager.shared.showAlert(title: "Success", message: "Profile updated successfully")
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: "Failed to update profile: \(error.localizedDescription)")
        }
        isLoadingUser = false
    }

    private func handleImageSelection() async {
        guard let image = selectedImage, let user = currentUser else { return }
        guard let data = image.toData() else {
            AlertManager.shared.showAlert(title: "Error", message: "Could not convert image to JPEG data")
            selectedImage = nil
            return
        }
        selectedImage = nil
        isLoadingAvatar = true
        defer { isLoadingAvatar = false }

        do {
            // Delete old avatar from storage before uploading the new one
            if let oldStorageId = user.avatarStorageId {
                do { try await ConvexChatAPI.shared.deleteFile(storageId: oldStorageId) }
                catch { print("⚠️ Could not delete old avatar \(oldStorageId): \(error)") }
            }
            let storageId = try await ConvexChatAPI.shared.uploadFile(data: data, mimeType: "image/jpeg")
            if let localURL = saveAvatarToLocalCache(data: data) {
                ConvexFileCacheService.shared.replaceCachedFile(storageId: storageId, with: localURL)
            }
            try await ConvexChatAPI.shared.updateUserAvatar(userId: user.id, storageId: storageId)
            // Update in-memory user so the next replacement knows the current storageId
            currentUser = ChatUser(
                id: user.id, name: user.name, username: user.username,
                email: user.email, avatarStorageId: storageId, bio: user.bio
            )
            profileAvatarImage = image
            AlertManager.shared.showAlert(title: "Success", message: "Profile picture updated successfully")
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: "Failed to update profile picture: \(error.localizedDescription)")
        }
    }

    private func saveAvatarToLocalCache(data: Data) -> URL? {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let assetsDirectory = documentsDirectory.appendingPathComponent("ChatAssets", isDirectory: true)
        if !fileManager.fileExists(atPath: assetsDirectory.path) {
            try? fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        }

        let fileURL = assetsDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }
}

// ... existing code ...

// Supporting Views
struct SettingsSection<Content: View>: View {
    let title: String
    let padding: CGFloat
    let content: Content
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.title = title
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                .padding(.leading, 4)
                .padding(.horizontal, padding)
                .padding(.top, 16)

            content
        }
    }
}

struct ThemeButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: themeIcon(for: theme))
                    .font(.title3)
                Text(theme.rawValue)
                    .font(.headline)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                        .symbolEffect(.bounce, value: isSelected)
                }
            }
            .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedTheme.colors(for: colorScheme).cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected
                            ? selectedTheme.colors(for: colorScheme).accent.opacity(0.5)
                            : selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// A settings row with a trailing toggle instead of a chevron.
struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let color: Color
    @Binding var isOn: Bool
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 32)

            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
            }
            .tint(selectedTheme.colors(for: colorScheme).accent)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 32)

            Text(title)
                .font(.headline)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}

private func themeIcon(for theme: AppTheme) -> String {
    switch theme {
    case .basic: return "circle.grid.cross.fill"
    case .cyberpunk: return "bolt.circle.fill"
    case .retroWave: return "sunset.fill"
    case .neonNight: return "sparkles"
    case .deepOcean: return "water.waves"
    case .bioOrganic: return "leaf.fill"
    case .vaultNoir: return "shield.lefthalf.filled"
    case .risographPop: return "circle.hexagongrid.fill"
    }
}

private struct ThemeRowContent: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        HStack {
            Image(systemName: themeIcon(for: selectedTheme))
                .font(.headline)
                .foregroundStyle(
                    selectedTheme.colors(for: colorScheme).accent
                )
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Theme")
                    .font(.headline)
                    .foregroundStyle(
                        selectedTheme.colors(for: colorScheme).textPrimary
                    )

                Text(selectedTheme.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(
                        selectedTheme.colors(for: colorScheme).textSecondary
                    )
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(
                    selectedTheme.colors(for: colorScheme).textSecondary
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    selectedTheme.colors(for: colorScheme).cardBackground
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    selectedTheme.colors(for: colorScheme).textSecondary
                        .opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}

// Add shimmer effect for loading state
struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        .gray.opacity(0.1),
                        .gray.opacity(0.3),
                        .gray.opacity(0.1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.5),
                                    .clear,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: -geometry.size.width)
                        .offset(x: 2 * geometry.size.width * phase)
                        .animation(
                            .linear(duration: 1.5).repeatForever(autoreverses: false),
                            value: phase
                        )
                }
            )
            .onAppear {
                phase = 1
            }
            .clipped()
    }
}

private struct ProfileTextField: View {
    let title: String
    @Binding var text: String
    let icon: String
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)

            TextField(title, text: $text)
                .textFieldStyle(.plain)
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .autocapitalization(.none)
                .keyboardType(icon == "at" || icon == "envelope.fill" ? .emailAddress : .default)
                #endif
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    selectedTheme.colors(for: colorScheme).accent.opacity(0.2),
                    lineWidth: 1
                )
        )
    }
}

// Data Migration Sheet
struct DataMigrationSheet: View {
    @Binding var selectedExportFile: URL?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    @State private var availableExports: [URL] = []
    @State private var showingExportsBrowser: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data Migration")
                            .font(.title2.bold())
                        Text("Manage locally cached data export files.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                    VStack(alignment: .leading, spacing: 16) {
                        Text("EXPORT DATA")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        Text("Data export is not available in this version.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                            )
                            .padding(.horizontal)
                    }

                    if !availableExports.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("EXPORT FILES")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            List {
                                ForEach(availableExports, id: \.self) { exportFile in
                                    Button {
                                        selectedExportFile = exportFile
                                    } label: {
                                        HStack {
                                            Image(systemName: "doc.fill")
                                                .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(exportFile.lastPathComponent)
                                                    .font(.caption.bold())
                                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                                                HStack(spacing: 6) {
                                                    Text(formatFileDate(exportFile))
                                                    Text("•")
                                                    Text(formatFileSize(exportFile))
                                                }
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if selectedExportFile == exportFile {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedExportFile == exportFile
                                                ? selectedTheme.colors(for: colorScheme).accent.opacity(0.1)
                                                : selectedTheme.colors(for: colorScheme).cardBackground)
                                            .padding(.vertical, 4)
                                    )
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteExportFile(exportFile)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            showingExportsBrowser = true
                                        } label: {
                                            Label("Browse", systemImage: "folder")
                                        }
                                    }
                                }
                            }
                            .frame(height: CGFloat(availableExports.count) * 80)
                            .listStyle(.plain)
                            .scrollDisabled(true)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(selectedTheme.colors(for: colorScheme).background)
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
                }
            }
            .onAppear {
                scanForExportFiles()
            }
            .sheet(isPresented: $showingExportsBrowser) {
                ExportsBrowserView()
            }
        }
    }

    private func scanForExportFiles() {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        guard let contents = try? fileManager.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: [.creationDateKey]) else {
            availableExports = []
            return
        }

        availableExports = contents
            .filter { $0.lastPathComponent.hasPrefix("migration_export_") && $0.pathExtension == "json" }
            .sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }
    }

    private func formatFileDate(_ url: URL) -> String {
        guard let creationDate = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else {
            return "Unknown date"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: creationDate)
    }

    private func formatFileSize(_ url: URL) -> String {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize > 0 else { return "0 B" }
        let bytes = Double(fileSize)
        let units = ["B", "KB", "MB", "GB", "TB"]
        let idx = min(Int(log2(bytes) / 10.0), units.count - 1)
        let size = bytes / pow(1024, Double(idx))
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = size < 10 ? 2 : 1
        formatter.minimumFractionDigits = 0
        let sizeString = formatter.string(from: NSNumber(value: size)) ?? String(format: "%.1f", size)
        return "\(sizeString) \(units[idx])"
    }

    private func deleteExportFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            if selectedExportFile == url { selectedExportFile = nil }
            scanForExportFiles()
            AlertManager.shared.showAlert(title: "Deleted", message: "Export file deleted successfully")
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: "Failed to delete file: \(error.localizedDescription)")
        }
    }
}

// Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
    }
}

#Preview {
    SettingsView()
}
