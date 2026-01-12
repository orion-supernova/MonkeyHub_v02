import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var cloudKit = CloudKitManager.shared
    @State private var showingSignOutAlert = false
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
    @StateObject private var navigationState = NavigationStateManager.shared
    @StateObject private var migrationManager = DataMigrationManager.shared
    @State private var showingMigrationSheet = false
    @State private var showingEnvironmentAlert = false
    @State private var showingClearDataAlert = false
    @State private var showingForceReloginAlert = false
    @State private var selectedExportFile: URL?  // ← Persistent across sheet dismissals


    private func signOut() async {
        userDefaults.set(nil, forKey: userIdUserDefaultsKey)
        cloudKit.isAuthenticated = false
    }

    private func forceRelogin() async {
        do {
            // Clear all local data
            try migrationManager.clearAllLocalData()

            // Clear CloudKit authentication state
            cloudKit.isAuthenticated = false

            // Clear environment preference to reset it
            UserDefaults.standard.removeObject(forKey: "cloudKitEnvironment")

            AlertManager.shared.showAlert(
                title: "Success",
                message: "All data cleared. You will be redirected to login."
            )
        } catch {
            AlertManager.shared.showAlert(
                title: "Error",
                message: "Failed to clear data: \(error.localizedDescription)"
            )
        }
    }

    private var themeSection: some View {
        SettingsSection(title: "APPEARANCE", padding: 24) {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    isShowingThemeSheet = true
                }
            } label: {
                ThemeRowContent()
            }
            .buttonStyle(.plain)
        }
    }

    private var developerSection: some View {
        SettingsSection(title: "DEVELOPER TOOLS") {
            VStack(spacing: 16) {
                // Environment info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cloud.fill")
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CloudKit Environment")
                                .font(.headline)
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                            Text(cloudKit.currentEnvironment.displayName)
                                .font(.subheadline)
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                        }
                        Spacer()
                        Button {
                            showingEnvironmentAlert = true
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.footnote.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                        }
                    }
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

                // Data migration button
                Button {
                    showingMigrationSheet = true
                } label: {
                    SettingsRow(
                        icon: "arrow.up.arrow.down.circle",
                        title: "Data Migration",
                        color: selectedTheme.colors(for: colorScheme).accent
                    )
                }

                // Clear local data button
                Button {
                    showingClearDataAlert = true
                } label: {
                    SettingsRow(
                        icon: "trash.circle",
                        title: "Clear Local Data",
                        color: selectedTheme.colors(for: colorScheme).destructive
                    )
                }

                // Force re-login button
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
                SettingsRow(
                    icon: "bell",
                    title: "Notifications",
                    color: selectedTheme.colors(for: colorScheme).accent
                )

                SettingsRow(
                    icon: "lock.fill",
                    title: "Privacy",
                    color: selectedTheme.colors(for: colorScheme).accent
                )

                Button {
                    showingSignOutAlert = true
                } label: {
                    SettingsRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "Sign Out",
                        color: selectedTheme.colors(for: colorScheme).destructive
                    )
                }
            }
        }
    }

    private func loadCurrentUser() async {
        isLoadingUser = true
        defer { isLoadingUser = false }

        do {
            currentUser = try await CloudKitManager.shared.fetchCurrentUser()
        } catch {
            AlertManager.shared.showAlert(
                title: "Error",
                message: "Failed to load user: \(error.localizedDescription)"
            )
        }
    }

    private var profileSection: some View {
        VStack(spacing: 24) {
            // Profile Picture with edit button
            ZStack {
                if let selectedImage = selectedImage {
                    Image(platformImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .shadow(
                            color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3),
                            radius: 10,
                            y: 5
                        )
                } else if let avatarAsset = currentUser?.avatarAsset,
                    let avatarUrl = avatarAsset.fileURL,
                    let imageData = try? Data(contentsOf: avatarUrl),
                    let image = PlatformImage.fromData(imageData)
                {
                    Image(platformImage: image)
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
                            Text(currentUser?.name.prefix(1).uppercased() ?? "?")
                                .font(.title.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                        }
                }

                // Edit button
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

            // User Info with edit button
            VStack(spacing: 8) {
                if isEditingProfile {
                    // Edit mode
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

                        // Save/Cancel buttons
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
                    // Display mode
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
                            Text(currentUser?.name ?? "Unknown")
                                .font(.title2.bold())

                            Text(
                                currentUser?.username.isEmpty == true
                                    ? "No username" : "@\(currentUser?.username ?? "")"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            Text(currentUser?.email ?? "No email")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
                .onChange(of: selectedImage) { _ in
                    if selectedImage != nil {
                        Task {
                            await handleImageSelection()
                        }
                    }
                }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    let headerHeight = geometry.size.height * 0.4
                    
                    // Header background
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).headerBackground,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    .frame(height: headerHeight)

                    ScrollView {
                        VStack(spacing: 0) {
                            // Profile Section
                            profileSection
                                .padding(.top, 40)
                                .padding(.bottom, 32)

                            // Settings Sections
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
            DataMigrationSheet(
                migrationManager: migrationManager,
                selectedExportFile: $selectedExportFile
            )
            .interactiveDismissDisabled(true)
        }
        .alert("Switch Environment", isPresented: $showingEnvironmentAlert) {
            Button("Development") {
                cloudKit.setEnvironment(.development)
            }
            Button("Production") {
                cloudKit.setEnvironment(.production)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select the CloudKit environment you want to use. Current: \(cloudKit.currentEnvironment.displayName)")
        }
        .alert("Clear Local Data", isPresented: $showingClearDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                Task {
                    do {
                        try migrationManager.clearAllLocalData()
                        AlertManager.shared.showAlert(
                            title: "Success",
                            message: "All local data has been cleared. Please restart the app."
                        )
                    } catch {
                        AlertManager.shared.showAlert(
                            title: "Error",
                            message: "Failed to clear data: \(error.localizedDescription)"
                        )
                    }
                }
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
            Text("This will clear all local data and authentication state, forcing you to sign in again. Use this if you're experiencing issues switching between CloudKit environments.")
        }
        .task {
            await loadCurrentUser()
        }
        .withAlertManager()
    }

    private func startEditing() {
        editingName = currentUser?.name ?? ""
        editingUsername = currentUser?.username ?? ""
        editingEmail = currentUser?.email ?? ""
        isEditingProfile = true
    }

    private func saveProfileChanges() async {
        guard let existingUser = currentUser else { return }

        let updatedUser = ChatUser(
            from: existingUser,
            name: editingName,
            username: editingUsername,
            email: editingEmail
        )

        do {
            // Save to CloudKit
            try await CloudKitManager.shared.updateUser(updatedUser)

            // Close edit mode
            await MainActor.run {
                isEditingProfile = false
                // Clear current user to show loading state
                currentUser = nil
                isLoadingUser = true
            }

            // Add a small delay to ensure CloudKit sync
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

            // Fetch fresh data
            let freshUser = try await CloudKitManager.shared.fetchCurrentUser()

            // Update UI on main thread
            await MainActor.run {
                withAnimation {
                    self.currentUser = freshUser
                    self.isLoadingUser = false
                }
            }

            // Show success message
            AlertManager.shared.showAlert(
                title: "Success",
                message: "Profile updated successfully"
            )
        } catch {
            await MainActor.run {
                isLoadingUser = false
            }
            AlertManager.shared.showAlert(
                title: "Error",
                message: "Failed to update profile: \(error.localizedDescription)"
            )
        }
    }

    private func handleImageSelection() async {
        guard let image = selectedImage, let user = currentUser else { return }

        do {
            isLoadingUser = true
            try await CloudKitManager.shared.updateUserProfilePicture(user, image: image)

            // Fetch updated user data
            let freshUser = try await CloudKitManager.shared.fetchCurrentUser()

            await MainActor.run {
                withAnimation {
                    self.currentUser = freshUser
                    self.isLoadingUser = false
                }
            }

            AlertManager.shared.showAlert(
                title: "Success",
                message: "Profile picture updated successfully"
            )
        } catch {
            await MainActor.run {
                isLoadingUser = false
            }
            AlertManager.shared.showAlert(
                title: "Error",
                message: "Failed to update profile picture: \(error.localizedDescription)"
            )
        }
    }
}

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
    }
}

// Add a separate view for theme row content
private struct ThemeRowContent: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        HStack {
            // Theme icon
            Image(systemName: themeIcon(for: selectedTheme))
                .font(.headline)
                .foregroundStyle(
                    selectedTheme.colors(for: colorScheme).accent
                )
                .frame(width: 32)

            // Theme info
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

// Add this helper view
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
    @ObservedObject var migrationManager: DataMigrationManager
    @Binding var selectedExportFile: URL?  // ← Now a binding from parent
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    @State private var availableExports: [URL] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Info Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data Migration")
                            .font(.title2.bold())
                        Text("Export your cached data to a file, then import it to CloudKit in a different environment.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                    // Stats Section
                    let stats = migrationManager.getDiskUsageStatsSync()
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            StatCard(title: "Rooms", value: "\(stats.rooms)", icon: "bubble.left.and.bubble.right.fill")
                            StatCard(title: "Messages", value: "\(stats.messages)", icon: "message.fill")
                        }
                        StatCard(title: "Storage", value: stats.totalSize, icon: "internaldrive.fill")
                    }
                    .padding(.horizontal)

                    // Export Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("EXPORT DATA")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        if migrationManager.isExporting {
                            VStack(spacing: 12) {
                                ProgressView(value: migrationManager.progress)
                                    .progressViewStyle(.linear)
                                Text(migrationManager.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                            )
                            .padding(.horizontal)
                        } else {
                            Button {
                                Task { @MainActor in
                                    do {
                                        let exportUrl = try await migrationManager.exportDataToDisk()
                                        // Ensure state update happens on main thread
                                        selectedExportFile = exportUrl

                                        // Refresh available exports list
                                        scanForExportFiles()

                                        // Small delay to ensure UI updates before alert
                                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

                                        AlertManager.shared.showAlert(
                                            title: "Export Complete",
                                            message: "Data exported to: \(exportUrl.lastPathComponent)\n\nScroll down to see the Import section."
                                        )
                                    } catch {
                                        AlertManager.shared.showAlert(
                                            title: "Export Failed",
                                            message: error.localizedDescription
                                        )
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export to File")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(selectedTheme.colors(for: colorScheme).accent)
                                )
                                .foregroundStyle(.white)
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Import Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("IMPORT TO CLOUDKIT")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        if migrationManager.isImporting {
                            VStack(spacing: 12) {
                                ProgressView(value: migrationManager.progress)
                                    .progressViewStyle(.linear)
                                Text(migrationManager.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                            )
                            .padding(.horizontal)
                        } else if !availableExports.isEmpty {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Select an export file to import:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Swipe to delete")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                                    }
                                }
                                .frame(height: CGFloat(availableExports.count) * 80)
                                .listStyle(.plain)
                                .scrollDisabled(true)

                                if let exportFile = selectedExportFile {
                                    VStack(spacing: 12) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.orange)
                                            Text("This will DELETE all existing data in CloudKit and replace it with the export file.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(.orange.opacity(0.1))
                                        )

                                        Button {
                                            Task {
                                                do {
                                                    try await migrationManager.importDataToCloudKit(fromFile: exportFile)
                                                    AlertManager.shared.showAlert(
                                                        title: "Import Complete",
                                                        message: "All data has been uploaded to CloudKit"
                                                    )
                                                } catch {
                                                    AlertManager.shared.showAlert(
                                                        title: "Import Failed",
                                                        message: error.localizedDescription
                                                    )
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: "square.and.arrow.down")
                                                Text("Import & Replace All CloudKit Data")
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(selectedTheme.colors(for: colorScheme).accent)
                                            )
                                            .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.top, 8)
                                }
                            }
                        } else {
                            Text("Export data first, then import it to CloudKit")
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
                    }
                }
                .padding(.vertical)
            }
            .background(selectedTheme.colors(for: colorScheme).background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                scanForExportFiles()
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

        // Filter for migration export files and sort by date (newest first)
        let exports = contents
            .filter { $0.lastPathComponent.hasPrefix("migration_export_") && $0.pathExtension == "json" }
            .sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }

        availableExports = exports

        // If we have a newly created export, select it
        if let selectedFile = selectedExportFile, exports.contains(selectedFile) {
            // Keep current selection
        } else if let mostRecent = exports.first {
            // Auto-select most recent export
            selectedExportFile = mostRecent
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
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            let bytes = Double(values.fileSize ?? 0)
            if bytes <= 0 { return "0 B" }
            let units = ["B", "KB", "MB", "GB", "TB"]
            let idx = min(Int(log2(bytes) / 10.0), units.count - 1)
            let size = bytes / pow(1024, Double(idx))
            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = size < 10 ? 2 : 1
            formatter.minimumFractionDigits = 0
            let sizeString = formatter.string(from: NSNumber(value: size)) ?? String(format: "%.1f", size)
            return "\(sizeString) \(units[idx])"
        } catch {
            return "—"
        }
    }

    private func deleteExportFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)

            // If deleted file was selected, clear selection
            if selectedExportFile == url {
                selectedExportFile = nil
            }

            // Refresh the list
            scanForExportFiles()

            AlertManager.shared.showAlert(
                title: "Deleted",
                message: "Export file deleted successfully"
            )
        } catch {
            AlertManager.shared.showAlert(
                title: "Error",
                message: "Failed to delete file: \(error.localizedDescription)"
            )
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

