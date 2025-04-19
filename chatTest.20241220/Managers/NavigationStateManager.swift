import SwiftUI

class NavigationStateManager: ObservableObject {
    static let shared = NavigationStateManager()

    enum Screen {
        case home
        case chatRoom
        case profile
        case settings
    }

    @Published var currentScreen: Screen = .home

    private init() {}

    var shouldShowFloatingMenu: Bool {
        currentScreen == .home
    }
}
