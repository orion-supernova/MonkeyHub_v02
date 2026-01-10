import SwiftUI
#if canImport(UIKit)
import UIKit  // For UIImpactFeedbackGenerator
#endif

struct BaseView: View {
    @State private var selectedTab: Tab = .chat
    @State private var isMenuExpanded = false
    @State private var menuButtonRotation = 0.0
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var navigationState = NavigationStateManager.shared

    enum Tab: String, CaseIterable {
        case chat = "Chat"
        case feed = "Feed"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .feed: return "newspaper.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    // MARK: - Body
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Main content
            Group {
                switch selectedTab {
                case .chat:
                    ContentView()
                case .feed:
                    FeedView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating Menu - only show when on home screen
            if navigationState.shouldShowFloatingMenu {
                FloatingMenu(
                    isExpanded: $isMenuExpanded,
                    selectedTab: $selectedTab,
                    rotation: $menuButtonRotation
                )
                .padding(24)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: navigationState.currentScreen)
    }
}

// MARK: - Floating Menu Struct
struct FloatingMenu: View {
    @Binding var isExpanded: Bool
    @Binding var selectedTab: BaseView.Tab
    @Binding var rotation: Double
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body
    var body: some View {
        ZStack {
            // Menu items
            ForEach(BaseView.Tab.allCases.indices, id: \.self) { index in
                let tab = BaseView.Tab.allCases[index]
                MenuButton(
                    icon: tab.icon,
                    isSelected: selectedTab == tab,
                    distance: isExpanded ? 82.0 : 0,
                    angle: -.pi / 2.2 + .pi / 4.5 * Double(index),
                    action: {
                        withAnimation(.spring(duration: 0.3)) {
                            selectedTab = tab
                            isExpanded = false
                            rotation = 0
                        }
                    }
                )
            }

            // Main menu button
            Button {
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                    isExpanded.toggle()
                    rotation = isExpanded ? 45 : 0
                }

                // Haptic feedback
                #if canImport(UIKit)
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                #endif
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(
                            color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3),
                            radius: 8,
                            y: 4
                        )

                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                        .rotationEffect(.degrees(rotation))
                }
            }
        }
    }
}

struct MenuButton: View {
    let icon: String
    let isSelected: Bool
    let distance: Double
    let angle: Double
    let action: () -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? selectedTheme.colors(for: colorScheme).primary
                            : [selectedTheme.colors(for: colorScheme).cardBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .shadow(
                    color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.2),
                    radius: 6,
                    y: 3
                )
                .overlay {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(
                            isSelected
                                ? selectedTheme.colors(for: colorScheme).text
                                : selectedTheme.colors(for: colorScheme).textSecondary
                        )
                }
        }
        .offset(
            x: cos(angle) * distance,
            y: sin(angle) * distance
        )
        .scaleEffect(isSelected ? 1.08 : 1.0)
        .animation(.spring(duration: 0.3), value: isSelected)
    }
}

// MARK: - Preview
#Preview {
    BaseView()
}
