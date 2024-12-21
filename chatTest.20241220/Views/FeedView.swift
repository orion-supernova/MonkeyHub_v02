import SwiftUI

struct FeedView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

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

                            Text("Feed")
                                .font(.title.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                        }
                        .padding(24)

                        // Content area with rounded corners
                        VStack(spacing: 16) {
                            Text("Coming Soon")
                                .font(.title2.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
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
        }
    }
}
