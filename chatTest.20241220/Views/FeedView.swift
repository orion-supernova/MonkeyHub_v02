import SwiftUI

struct FeedView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

                        // Content area with rounded corners
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

                                VStack(spacing: 8) {
                                    Text("Feed Coming Soon")
                                        .font(.title2.bold())
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).textPrimary)

                                    Text(
                                        "Get ready for a more authentic social experience!\nComing very soon."
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        selectedTheme.colors(for: colorScheme).textSecondary
                                    )
                                    .multilineTextAlignment(.center)
                                }

                                // Feature preview
                                VStack(spacing: 16) {
                                    FeaturePreviewRow(
                                        icon: "camera.viewfinder",
                                        title: "Daily Moments",
                                        description: "Share authentic snapshots of your day"
                                    )

                                    FeaturePreviewRow(
                                        icon: "clock.arrow.2.circlepath",
                                        title: "Time Window",
                                        description: "Post within random 2-minute windows"
                                    )

                                    FeaturePreviewRow(
                                        icon: "photo.stack",
                                        title: "Story Highlights",
                                        description: "Keep your favorite moments forever"
                                    )

                                    FeaturePreviewRow(
                                        icon: "face.smiling",
                                        title: "Real Reactions",
                                        description: "React with your authentic expressions"
                                    )

                                    FeaturePreviewRow(
                                        icon: "person.2.wave.2",
                                        title: "Friend Activities",
                                        description: "See when friends are online and chatting"
                                    )
                                }
                                .padding(.top, 8)
                            }
                            .padding(24)
                        }
                        .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 16)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 32)
                                    .fill(selectedTheme.colors(for: colorScheme).background)
                                    .shadow(
                                        color: selectedTheme.colors(for: colorScheme).primary[0]
                                            .opacity(0.15),
                                        radius: 24,
                                        y: -12
                                    )

                                Rectangle()
                                    .fill(selectedTheme.colors(for: colorScheme).background)
                                    .frame(height: 60)
                                    .offset(y: -30)
                            }
                        )
                        .offset(y: -40)
                        .padding(.top, 40)
                    }
                }
            }
            .background(selectedTheme.colors(for: colorScheme).background)
        }
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
