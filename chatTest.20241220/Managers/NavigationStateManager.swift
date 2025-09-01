import SwiftUI

class NavigationStateManager: ObservableObject {
    static let shared = NavigationStateManager()

    enum Screen {
        case home
        case chatRoom
        case settings
        case feedView
    }

    @Published var currentScreen: Screen = .home

    private init() {}

    var shouldShowFloatingMenu: Bool {
        currentScreen == .home || currentScreen == .feedView || currentScreen == .settings
    }
}
