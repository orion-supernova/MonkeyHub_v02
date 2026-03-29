import Foundation

enum FriendshipStatus: String, Codable, Hashable {
    case none
    case friend
    case outgoingPending
    case incomingPending

    var actionLabel: String {
        switch self {
        case .none:
            return "Message Request"
        case .friend:
            return "Choose Room Type"
        case .outgoingPending:
            return "Pending Request"
        case .incomingPending:
            return "Review Request"
        }
    }
}
