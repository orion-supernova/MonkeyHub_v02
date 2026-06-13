import SwiftUI

struct FeedView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale
    @StateObject private var navigationState = NavigationStateManager.shared


    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    let headerHeight = geometry.size.height * 0.5
                    
                    // Header background with dynamic height
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).headerBackground,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    .frame(height: headerHeight)  // Use dynamic height

                    ScrollView {
                        VStack(spacing: 0) {
                            // Header content
                            VStack(spacing: 20) {
                                // Status bar spacing
                                Color.clear
                                    .frame(height: 50)

                                // Title and subtitle
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Feed")
                                        .font(.title.bold())
                                        .foregroundStyle(selectedTheme.colors(for: colorScheme).text)

                                    Text("Share moments, connect with friends")
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).text.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 24)
                            .padding(.bottom, 32)

                            // Content area with improved corner radius effect
                            VStack(spacing: 24) {
                                // Coming soon illustration
                                VStack(spacing: 24) {
                                    // Decorative elements
                                    HStack(spacing: 16) {
                                        ForEach(0..<3) { index in
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: selectedTheme.colors(for: colorScheme)
                                                            .primary,
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 12, height: 12)
                                                .opacity(0.5 + Double(index) * 0.2)
                                        }
                                    }

                                    Image(systemName: "newspaper.fill")
                                        .font(.system(size: 64))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: selectedTheme.colors(for: colorScheme).primary,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .padding(.bottom, 8)

                                    FriendsPresenceFeed()
                                        .padding(.top, 8)
                                }
                                .padding(24)
                            }
                            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
                            .background(
                                ZStack {
                                    // Main background with enhanced shadow and corner radius
                                    RoundedRectangle(cornerRadius: 32)
                                        .fill(selectedTheme.colors(for: colorScheme).background)
                                        .shadow(
                                            color: selectedTheme.colors(for: colorScheme).primary[0]
                                                .opacity(0.2),
                                            radius: 32,
                                            y: -16
                                        )

                                    // Top overlay for smooth transition
                                    VStack(spacing: 0) {
                                        // Gradient overlay for smoother transition
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

                                        // Background fill
                                        Rectangle()
                                            .fill(selectedTheme.colors(for: colorScheme).background)
                                    }
                                    .mask(
                                        RoundedRectangle(cornerRadius: 32)
                                    )
                                }
                            )
                            .mask(
                                // Mask to ensure content respects corner radius
                                RoundedRectangle(cornerRadius: 32)
                            )
                            .offset(y: -60)
                            .padding(.top, 60)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(selectedTheme.colors(for: colorScheme).background)
        }
        .onAppear {
            navigationState.currentScreen = .feedView
        }
    }
}

// MARK: - Friends Presence Feed

/// Live presence feed: friends sorted online-first, with status + last-seen.
struct FriendsPresenceFeed: View {
    @ObservedObject private var repository = ChatRepository.shared
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ThemeColors { selectedTheme.colors(for: colorScheme) }

    private var sortedFriends: [ChatUser] {
        repository.friends.sorted { a, b in
            if a.isOnline != b.isOnline { return a.isOnline }
            return (a.lastSeen ?? .distantPast) > (b.lastSeen ?? .distantPast)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FRIENDS")
                    .font(.caption.bold())
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                let onlineCount = repository.friends.filter { $0.isOnline }.count
                if onlineCount > 0 {
                    Text("\(onlineCount) online")
                        .font(.caption.bold())
                        .foregroundStyle(theme.accent)
                }
            }

            if sortedFriends.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.system(size: 36))
                        .foregroundStyle(theme.textSecondary)
                    Text("No friends yet")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(sortedFriends) { friend in
                    PresenceRow(friend: friend, theme: theme)
                }
            }
        }
    }
}

private struct PresenceRow: View {
    let friend: ChatUser
    let theme: ThemeColors

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(LinearGradient(colors: theme.primary, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Text(friend.displayInitial)
                            .font(.headline.bold())
                            .foregroundStyle(theme.text)
                    )
                if friend.isOnline {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(theme.background, lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text(presenceText)
                    .font(.caption)
                    .foregroundStyle(friend.isOnline ? Color.green : theme.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.cardBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.textSecondary.opacity(0.08), lineWidth: 1)
        )
    }

    private var presenceText: String {
        if friend.isOnline { return "Online" }
        if friend.status == "away" { return "Away" }
        guard let lastSeen = friend.lastSeen else { return "Offline" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Last seen \(formatter.localizedString(for: lastSeen, relativeTo: Date()))"
    }
}

struct FeaturePreviewRow: View {
    let icon: String
    let title: String
    let description: String
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .background(
                    selectedTheme.colors(for: colorScheme).cardBackground
                        .opacity(0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    selectedTheme.colors(for: colorScheme).accent.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
}

#Preview {
    FeedView()
}
