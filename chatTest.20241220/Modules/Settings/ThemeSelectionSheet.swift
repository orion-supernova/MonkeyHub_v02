import SwiftUI

struct ThemeSelectionSheet: View {
    @Binding var isShowingSheet: Bool
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var animateContent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        ThemePreviewButton(
                            theme: theme,
                            isSelected: selectedTheme == theme
                        ) {
                            withAnimation(.spring(duration: 0.4)) {
                                selectedTheme = theme
                            }
                        }
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Select Theme")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if canImport(UIKit)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            isShowingSheet = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button {
                        withAnimation {
                            isShowingSheet = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    }
                }
                #endif
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                animateContent = true
            }
        }
    }
}

struct ThemePreviewButton: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Theme preview circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: theme.colors(for: colorScheme).primary,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: themeIcon(for: theme))
                            .font(.headline)
                            .foregroundStyle(theme.colors(for: colorScheme).text)
                    )
                    .shadow(
                        color: theme.colors(for: colorScheme).primary[0].opacity(0.3),
                        radius: 8,
                        y: 4
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.rawValue)
                        .font(.headline)
                        .foregroundStyle(theme.colors(for: colorScheme).textPrimary)

                    // Theme description
                    Text(themeDescription(for: theme))
                        .font(.subheadline)
                        .foregroundStyle(theme.colors(for: colorScheme).textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.colors(for: colorScheme).accent)
                        .symbolEffect(.bounce, value: isSelected)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.colors(for: colorScheme).primary[0].opacity(0.1),
                                theme.colors(for: colorScheme).primary[1].opacity(0.05),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(isSelected ? 1 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected
                            ? theme.colors(for: colorScheme).accent.opacity(0.5)
                            : theme.colors(for: colorScheme).textSecondary.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func themeDescription(for theme: AppTheme) -> String {
        switch theme {
        case .basic: return "Clean and minimal"
        case .cyberpunk: return "High-tech and vibrant"
        case .retroWave: return "80s retro vibes"
        case .neonNight: return "Dark with neon accents"
        case .deepOcean: return "Calm and professional"
        }
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

#Preview {
    ThemeSelectionSheet(isShowingSheet: .constant(true))
}
