import Foundation

/// Media kind for a 1:1 call.
enum CallType: String, Codable {
    case audio
    case video
}

/// Lifecycle status of a call session (mirrors the `calls.status` field).
enum CallStatus: String, Codable {
    case ringing
    case active
    case ended
    case rejected
    case missed
    case cancelled
    case failed

    /// True once the call has reached a non-recoverable end state.
    var isTerminal: Bool {
        switch self {
        case .ended, .rejected, .missed, .cancelled, .failed: return true
        case .ringing, .active: return false
        }
    }
}

/// A 1:1 voice/video call session. The actual SDP/ICE signaling rides on
/// `CallSignal` rows; this only tracks the session lifecycle.
struct Call: Identifiable, Equatable {
    let id: String
    let callerId: String
    let calleeId: String
    let roomId: String
    let type: CallType
    var status: CallStatus
    let startedAt: Date
    var acceptedAt: Date?
    var acceptingDeviceId: String?
    /// Display name of the other participant (hydrated by `activeCallForUser`).
    var peerName: String?
    /// Human-readable label of the callee device currently holding the call.
    var acceptingDeviceName: String?
    var acceptingPlatform: String?

    /// Whether `me` is the caller in this call.
    func isOutgoing(for userId: String) -> Bool { callerId == userId }

    /// The other participant's user id relative to `me`.
    func peerId(for userId: String) -> String { callerId == userId ? calleeId : callerId }

    static func == (lhs: Call, rhs: Call) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.acceptingDeviceId == rhs.acceptingDeviceId
    }
}

/// Kinds of WebRTC signaling messages exchanged between peers.
enum CallSignalKind: String, Codable {
    case invite
    case offer
    case answer
    case ice
    case state
    case bye
    case reject
    case cancel
    case taken
    case handoffPrepare = "handoff-prepare"
    case handoffTakeover = "handoff-takeover"
    case handoffOffer = "handoff-offer"
    case handoffAnswer = "handoff-answer"
}

/// A single signaling message. `payload` is JSON-encoded (SDP, ICE candidate,
/// or a state object) — decode per `kind` at the call layer.
struct CallSignal: Identifiable, Equatable {
    let id: String
    let callId: String
    let fromUserId: String
    let kind: CallSignalKind
    let payload: String
    let createdAt: Date
    var targetDeviceId: String?
    var fromDeviceId: String?

    static func == (lhs: CallSignal, rhs: CallSignal) -> Bool { lhs.id == rhs.id }
}

/// ICE server configuration returned by `calls:getIceConfig`.
struct IceServerConfig: Equatable {
    let urls: [String]
    let username: String?
    let credential: String?
}
