import SwiftUI
import UIKit  // For UIImpactFeedbackGenerator

struct BaseView: View {
    @State private var selectedTab: Tab = .chat
    @State private var isMenuExpanded = false
    @State private var menuButtonRotation = 0.0
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

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

            // Floating Menu
            FloatingMenu(
                isExpanded: $isMenuExpanded,
                selectedTab: $selectedTab,
                rotation: $menuButtonRotation
            )
            .padding(24)
        }
    }
}

struct FloatingMenu: View {
    @Binding var isExpanded: Bool
    @Binding var selectedTab: BaseView.Tab
    @Binding var rotation: Double
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Menu items
            ForEach(BaseView.Tab.allCases.indices, id: \.self) { index in
                let tab = BaseView.Tab.allCases[index]
                MenuButton(
                    icon: tab.icon,
                    title: tab.rawValue,
                    isSelected: selectedTab == tab,
                    distance: isExpanded ? 80.0 * Double(index + 1) : 0,
                    angle: Double.pi / 4 * Double(index),
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
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
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
    let title: String
    let isSelected: Bool
    let distance: Double
    let angle: Double
    let action: () -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            ZStack {
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
                    .frame(width: 48, height: 48)
                    .shadow(
                        color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.2),
                        radius: 6,
                        y: 3
                    )

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(
                        isSelected
                            ? selectedTheme.colors(for: colorScheme).text
                            : selectedTheme.colors(for: colorScheme).textSecondary
                    )
            }
            .overlay(alignment: .trailing) {
                if distance > 0 {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                                .shadow(
                                    color: selectedTheme.colors(for: colorScheme).primary[0]
                                        .opacity(0.1),
                                    radius: 4,
                                    y: 2
                                )
                        )
                        .offset(x: 60)
                        .opacity(distance > 0 ? 1 : 0)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .offset(
            x: cos(angle) * distance,
            y: -sin(angle) * distance
        )
    }
}
