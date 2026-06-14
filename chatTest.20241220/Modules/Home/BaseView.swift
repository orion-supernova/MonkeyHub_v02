import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Helper to map drag angle to the correct tab
extension BaseView.Tab {
    static func from(angle: Double) -> BaseView.Tab? {
        let tabs = BaseView.Tab.allCases
        // We use the same math logic as the button placement to find the closest tab
        return tabs.enumerated().min(by: { a, b in
            let angleA = -.pi / 2.2 + .pi / 4.5 * Double(a.offset)
            let angleB = -.pi / 2.2 + .pi / 4.5 * Double(b.offset)
            return abs(angleA - angle) < abs(angleB - angle)
        })?.element
    }
}

struct BaseView: View {
    @State private var selectedTab: Tab = .chat
    @AppStorage(AppearanceKeys.navStyle) private var navStyle = NavStyle.pill

    enum Tab: String, CaseIterable {
        case chat = "Chat", feed = "Feed", settings = "Settings"
        /// Outline glyph — the native tab bar fills it automatically when selected.
        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right"
            case .feed: return "newspaper"
            case .settings: return "gearshape"
            }
        }
        /// Always-filled glyph for the custom radial menu, which renders a single state.
        var filledIcon: String { icon + ".fill" }
    }

    var body: some View {
        switch navStyle {
        case .pill:
            // Custom floating pill (NOT the native TabView tab bar). The native bar's hide/show on
            // push/pop has an unavoidable restore delay on the way back; a custom overlay we drive
            // ourselves slides out/in *in sync* with the navigation transition. Same pattern as
            // `RadialContainer` below. Observation is isolated to the container subview.
            PillContainer(selectedTab: $selectedTab)
        case .radial:
            // The custom floating menu IS driven by navigation state, so its observation is
            // isolated to this subview.
            RadialContainer(selectedTab: $selectedTab)
        }
    }
}

/// Pill mode — custom floating `PillNav` overlay, shown/hidden via `shouldShowFloatingMenu`.
/// Replaces the native `TabView` tab bar so the bar slides out on push and back in *in sync* with
/// the pop (the native bar restores only after the pop completes — a visible delay).
private struct PillContainer: View {
    @Binding var selectedTab: BaseView.Tab
    @StateObject private var navigationState = NavigationStateManager.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .chat: ContentView()
                case .feed: FeedView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Hidden whenever the nav path is non-empty (i.e. inside a pushed room), so entering a
            // room slides the pill out and popping slides it back — driven by our own animation.
            if navigationState.shouldShowFloatingMenu {
                PillNav(selectedTab: $selectedTab)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: navigationState.shouldShowFloatingMenu)
    }
}

/// Radial orb mode — the custom overlay navigation, shown/hidden via `shouldShowFloatingMenu`.
/// Owns its own `NavigationStateManager` observation so the pill-mode `TabView` stays inert.
private struct RadialContainer: View {
    @Binding var selectedTab: BaseView.Tab
    @StateObject private var navigationState = NavigationStateManager.shared
    @State private var isMenuExpanded = false
    @State private var menuButtonRotation = 0.0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                switch selectedTab {
                case .chat: ContentView()
                case .feed: FeedView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if navigationState.shouldShowFloatingMenu {
                FloatingMenu(
                    isExpanded: $isMenuExpanded,
                    selectedTab: $selectedTab,
                    rotation: $menuButtonRotation
                )
                .padding(24)
            }
        }
        // The custom floating menu is shown/hidden manually, so animate its appearance.
        .animation(.spring(duration: 0.3), value: navigationState.currentScreen)
    }
}

/// Native bottom pill tab bar (default navigation style).
struct PillNav: View {
    @Binding var selectedTab: BaseView.Tab
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = selectedTheme.colors(for: colorScheme)
        HStack(spacing: 6) {
            ForEach(BaseView.Tab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedTab = tab }
                    #if canImport(UIKit)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                        if isSelected {
                            Text(tab.rawValue).font(.subheadline.weight(.semibold))
                        }
                    }
                    .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
                    .padding(.horizontal, isSelected ? 16 : 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(isSelected
                            ? AnyShapeStyle(LinearGradient(colors: theme.primary, startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.clear))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        // Native Liquid Glass capsule — same material the system tab bar uses.
        .glassEffect(.regular, in: .capsule)
    }
}

struct FloatingMenu: View {
    @Binding var isExpanded: Bool
    @Binding var selectedTab: BaseView.Tab
    @Binding var rotation: Double
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredTab: BaseView.Tab? = nil

    var body: some View {
        ZStack {
            // Menu items
            ForEach(BaseView.Tab.allCases.indices, id: \.self) { index in
                let tab = BaseView.Tab.allCases[index]
                MenuButton(
                    icon: tab.filledIcon,
                    isSelected: selectedTab == tab,
                    isHovered: hoveredTab == tab,
                    distance: isExpanded ? 90.0 : 0,
                    angle: -.pi / 2.2 + .pi / 4.5 * Double(index)
                )
            }

            // Main menu button
            mainButtonCircle
        }
    }

    var mainButtonCircle: some View {
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
                .shadow(color: selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3), radius: 8, y: 4)

            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                .rotationEffect(.degrees(rotation))
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // 1. Expand menu on touch
                    if !isExpanded {
                        withAnimation(.spring(duration: 0.4, bounce: 0.4)) {
                            isExpanded = true
                            rotation = 45
                        }
                        triggerImpactHaptic(style: .light)
                    }

                    // 2. Calculate drag location
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let distance = sqrt(dx*dx + dy*dy)
                    let angle = atan2(dy, dx)

                    // 3. Highlight button finger is over
                    if distance > 40 {
                        let newHover = BaseView.Tab.from(angle: angle)
                        if hoveredTab != newHover {
                            hoveredTab = newHover
                            triggerSelectionHaptic() // Selection changed haptic
                        }
                    } else {
                        hoveredTab = nil
                    }
                }
                .onEnded { value in
                    // 4. Select the hovered tab on release
                    if let finalTab = hoveredTab {
                        selectedTab = finalTab
                        triggerImpactHaptic(style: .medium)
                    }
                    
                    // 5. Collapse
                    withAnimation(.spring(duration: 0.3)) {
                        isExpanded = false
                        rotation = 0
                        hoveredTab = nil
                    }
                }
        )
    }
    
    // MARK: - Haptic Helpers
    private func triggerImpactHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    private func triggerSelectionHaptic() {
        #if canImport(UIKit)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }
}

struct MenuButton: View {
    let icon: String
    let isSelected: Bool
    let isHovered: Bool
    let distance: Double
    let angle: Double
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let themeColors = selectedTheme.colors(for: colorScheme)
        
        Circle()
            .fill(
                LinearGradient(
                    colors: (isSelected || isHovered) ? themeColors.primary : [themeColors.cardBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle((isSelected || isHovered) ? themeColors.text : themeColors.textSecondary)
            }
            .shadow(color: themeColors.primary[0].opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 10 : 6, y: 3)
            .scaleEffect(isHovered ? 1.3 : (isSelected ? 1.1 : 1.0))
            .offset(x: cos(angle) * distance, y: sin(angle) * distance)
            .animation(.spring(duration: 0.2), value: isHovered)
            .animation(.spring(duration: 0.2), value: isSelected)
    }
}
