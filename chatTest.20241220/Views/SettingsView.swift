import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var cloudKit = CloudKitManager.shared
    @State private var showingSignOutAlert = false

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
                .frame(height: 140)

                ScrollView {
                    VStack(spacing: 0) {
                        // Header content
                        VStack(spacing: 20) {
                            // Status bar spacing
                            Color.clear
                                .frame(height: 50)

                            Text("Settings")
                                .font(.title.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                        }
                        .padding(24)

                        // Content area with rounded corners
                        VStack(spacing: 24) {
                            // Theme selector
                            Section {
                                ForEach(AppTheme.allCases, id: \.self) { theme in
                                    Button {
                                        withAnimation(.spring(duration: 0.4)) {
                                            selectedTheme = theme
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: themeIcon(for: theme))
                                                .font(.title3)
                                            Text(theme.rawValue)
                                                .font(.headline)
                                            Spacer()
                                            if selectedTheme == theme {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(
                                                        selectedTheme.colors(for: colorScheme)
                                                            .accent
                                                    )
                                            }
                                        }
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).textPrimary
                                        )
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(
                                                    selectedTheme.colors(for: colorScheme)
                                                        .cardBackground)
                                        )
                                    }
                                }
                            } header: {
                                Text("APPEARANCE")
                                    .font(.caption.bold())
                                    .foregroundStyle(
                                        selectedTheme.colors(for: colorScheme).textSecondary
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button {
                                showingSignOutAlert = true
                            } label: {
                                Text("Sign Out")
                                    .font(.headline)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(
                                                selectedTheme.colors(for: colorScheme)
                                                    .cardBackground)
                                    )
                            }
                        }
                        .padding(24)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 32)
                                    .fill(selectedTheme.colors(for: colorScheme).background)
                                    .shadow(
                                        color: selectedTheme.colors(for: colorScheme).primary[0]
                                            .opacity(0.1),
                                        radius: 20,
                                        y: -10
                                    )

                                Rectangle()
                                    .fill(selectedTheme.colors(for: colorScheme).background)
                                    .frame(height: 50)
                                    .offset(y: -25)
                            }
                        )
                        .offset(y: -40)
                        .padding(.top, 40)
                    }
                }
            }
            .background(selectedTheme.colors(for: colorScheme).background)
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
        userDefaults.set(nil, forKey: userIdUserDefaultsKey)
        cloudKit.isAuthenticated = false
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
}
