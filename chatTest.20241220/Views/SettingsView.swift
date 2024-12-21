import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var cloudKit = CloudKitManager.shared
    @State private var showingSignOutAlert = false
    @State private var animateContent = false
    @State private var isShowingThemeSheet = false

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
                        VStack(spacing: 24) {
                            // Profile Picture
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: selectedTheme.colors(for: colorScheme).primary,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .shadow(
                                        color: selectedTheme.colors(for: colorScheme).primary[0]
                                            .opacity(0.3),
                                        radius: 10,
                                        y: 5
                                    )

                                Text("MC")
                                    .font(.title.bold())
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)

                                // Edit button
                                Circle()
                                    .fill(selectedTheme.colors(for: colorScheme).accent)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.caption.bold())
                                            .foregroundStyle(
                                                selectedTheme.colors(for: colorScheme).text)
                                    )
                                    .offset(x: 32, y: 32)
                            }
                            .offset(y: animateContent ? 0 : 20)
                            .opacity(animateContent ? 1 : 0)
                            .padding(.top, 20)

                            // User Info
                            VStack(spacing: 8) {
                                Text("Murat Can Koç")
                                    .font(.title2.bold())
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)

                                Text("@muratcankoc")
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        selectedTheme.colors(for: colorScheme).text.opacity(0.8))

                                Text("murat@example.com")
                                    .font(.footnote)
                                    .foregroundStyle(
                                        selectedTheme.colors(for: colorScheme).text.opacity(0.6))
                            }
                            .offset(y: animateContent ? 0 : 20)
                            .opacity(animateContent ? 1 : 0)
                        }
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
            withAnimation(.easeOut(duration: 0.6)) {
                animateContent = true
            }
        }
        .sheet(isPresented: $isShowingThemeSheet) {
            ThemeSelectionSheet(isShowingSheet: $isShowingThemeSheet)
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

#Preview {
    SettingsView()
}
