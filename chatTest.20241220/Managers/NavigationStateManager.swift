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
    @Published var currentRoomId: String? = nil  // Track active chatroom for notification suppression

    private init() {}

    var shouldShowFloatingMenu: Bool {
        currentScreen == .home || currentScreen == .feedView || currentScreen == .settings
    }
}
