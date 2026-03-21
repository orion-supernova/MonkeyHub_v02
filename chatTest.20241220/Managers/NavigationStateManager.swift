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
    @Published var path = NavigationPath()

    private init() {}

    func navigateToRoom(id: String) {
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenChatRoom"),
            object: nil,
            userInfo: ["roomId": id]
        )
    }

    func navigateToRoom(_ room: ChatRoom) {
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenChatRoom"),
            object: nil,
            userInfo: ["room": room]
        )
    }

    func navigateToDraftChat(_ draft: DraftDirectChatSession) {
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenDraftChat"),
            object: nil,
            userInfo: ["draft": draft]
        )
    }

    var shouldShowFloatingMenu: Bool {
        // Only show if we are on root View and not deep in navigation
        return (currentScreen == .home || currentScreen == .feedView || currentScreen == .settings) && path.isEmpty
    }
}
