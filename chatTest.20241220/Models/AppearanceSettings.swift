import Foundation

/// AppStorage keys for appearance/behavior preferences (mirrors the Flutter
/// SettingsStore). Centralized so views read the same key strings.
enum AppearanceKeys {
    static let roomLayout = "roomLayout"
    static let navStyle = "navStyle"
    static let chatStyle = "chatStyle"
    static let replyStyle = "replyStyle"
    static let captureProtection = "captureProtection"
    static let viewReadReceipts = "viewReadReceipts"
    static let showLinkUrls = "showLinkUrls"
}

/// Room list presentation.
enum RoomLayout: String, CaseIterable, Identifiable {
    case list, grid
    var id: String { rawValue }
    var label: String { self == .list ? "List" : "Grid" }
    var icon: String { self == .list ? "list.bullet" : "square.grid.2x2" }
}

/// Primary navigation chrome.
enum NavStyle: String, CaseIterable, Identifiable {
    case pill, radial
    var id: String { rawValue }
    var label: String { self == .pill ? "Bottom Pill" : "Radial Orb" }
    var icon: String { self == .pill ? "rectangle.bottomthird.inset.filled" : "circle.circle" }
}

/// Message density.
enum ChatStyle: String, CaseIterable, Identifiable {
    case compact, classic
    var id: String { rawValue }
    var label: String { self == .compact ? "Compact" : "Classic" }
    var icon: String { self == .compact ? "rectangle.compress.vertical" : "rectangle.expand.vertical" }
}

/// Visual treatment of the inline reply tether.
enum ReplyStyle: String, CaseIterable, Identifiable {
    case phantomEcho, stickyNote, comicTail, classic
    var id: String { rawValue }
    var label: String {
        switch self {
        case .phantomEcho: return "Phantom Echo"
        case .stickyNote: return "Sticky Note"
        case .comicTail: return "Comic Tail"
        case .classic: return "Classic"
        }
    }
}
