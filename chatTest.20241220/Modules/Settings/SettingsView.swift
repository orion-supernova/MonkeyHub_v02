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
    @State private var selectedImage: UIImage?
    @StateObject private var navigationState = NavigationStateManager.shared

    private var headerHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        return screenHeight * 0.4  // 40% of screen height
    }

    private func signOut() async {
        userDefaults.set(nil, forKey: userIdUserDefaultsKey)
        cloudKit.isAuthenticated = false
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
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .shadow(
                            color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3),
                            radius: 10,
                            y: 5
                        )
                } else if let avatarAsset = currentUser?.avatarAsset,
                    let avatarUrl = avatarAsset.fileURL,
                    let imageData = try? Data(contentsOf: avatarUrl),
                    let image = UIImage(data: imageData)
                {
                    Image(uiImage: image)
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
            ZStack(alignment: .top) {
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
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .autocapitalization(.none)
                .keyboardType(icon == "at" || icon == "envelope.fill" ? .emailAddress : .default)
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

#Preview {
    SettingsView()
}
