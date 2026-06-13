import Foundation
import ConvexMobile

// MARK: - Call documents

/// The hydrated active-call document returned by `calls:activeCallForUser`.
struct ConvexActiveCallDoc: Decodable {
    let _id: String
    let callerId: String
    let calleeId: String
    let roomId: String
    let type: String
    let status: String
    let startedAt: Double
    let acceptedAt: Double?
    let acceptingDeviceId: String?
    let peerName: String?
    let acceptingDeviceName: String?
    let acceptingPlatform: String?

    func toCall() -> Call {
        Call(
            id: _id,
            callerId: callerId,
            calleeId: calleeId,
            roomId: roomId,
            type: CallType(rawValue: type) ?? .audio,
            status: CallStatus(rawValue: status) ?? .ringing,
            startedAt: Date(timeIntervalSince1970: startedAt / 1000),
            acceptedAt: acceptedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            acceptingDeviceId: acceptingDeviceId,
            peerName: peerName,
            acceptingDeviceName: acceptingDeviceName,
            acceptingPlatform: acceptingPlatform
        )
    }
}

/// A signaling row returned by `calls:signalsForUser`.
struct ConvexCallSignalDoc: Decodable {
    let _id: String
    let callId: String
    let fromUserId: String
    let kind: String
    let payload: String
    let createdAt: Double
    let targetDeviceId: String?
    let fromDeviceId: String?

    func toCallSignal() -> CallSignal {
        CallSignal(
            id: _id,
            callId: callId,
            fromUserId: fromUserId,
            kind: CallSignalKind(rawValue: kind) ?? .state,
            payload: payload,
            createdAt: Date(timeIntervalSince1970: createdAt / 1000),
            targetDeviceId: targetDeviceId,
            fromDeviceId: fromDeviceId
        )
    }
}

/// `calls:getIceConfig` response. Each server's `urls` is a single string on
/// the backend; we normalize to an array for WebRTC consumption.
private struct ConvexIceConfigDoc: Decodable {
    struct Server: Decodable {
        let urls: String
        let username: String?
        let credential: String?
    }
    let iceServers: [Server]
}

// MARK: - Calls + VoIP token API

/// Convex operations for 1:1 voice/video calling, signaling, and per-device
/// push-token registration. Used by CallService / CallSignalingManager (Phase 3).
final class ConvexCallsAPI {
    static let shared = ConvexCallsAPI()
    private let convex = ConvexService.shared
    private init() {}

    // MARK: Call lifecycle

    /// Starts a call and returns the new call id.
    func initiate(callerId: String, calleeId: String, roomId: String, type: CallType) async throws -> String {
        try await convex.mutation("calls:initiate", with: [
            "callerId": callerId,
            "calleeId": calleeId,
            "roomId": roomId,
            "type": type.rawValue,
        ])
    }

    func accept(callId: String, userId: String, acceptingDeviceId: String?) async throws {
        var args: [String: ConvexEncodable?] = ["callId": callId, "userId": userId]
        if let acceptingDeviceId { args["acceptingDeviceId"] = acceptingDeviceId }
        try await convex.mutationVoid("calls:accept", with: args)
    }

    func reject(callId: String, userId: String, acceptingDeviceId: String? = nil) async throws {
        var args: [String: ConvexEncodable?] = ["callId": callId, "userId": userId]
        if let acceptingDeviceId { args["acceptingDeviceId"] = acceptingDeviceId }
        try await convex.mutationVoid("calls:reject", with: args)
    }

    func cancel(callId: String, userId: String) async throws {
        try await convex.mutationVoid("calls:cancel", with: ["callId": callId, "userId": userId])
    }

    func end(callId: String, userId: String) async throws {
        try await convex.mutationVoid("calls:end", with: ["callId": callId, "userId": userId])
    }

    func handoff(callId: String, userId: String, newDeviceId: String) async throws {
        try await convex.mutationVoid("calls:handoffCall", with: [
            "callId": callId,
            "userId": userId,
            "newDeviceId": newDeviceId,
        ])
    }

    // MARK: Signaling

    func sendSignal(
        callId: String,
        fromUserId: String,
        toUserId: String,
        kind: CallSignalKind,
        payload: String,
        targetDeviceId: String? = nil,
        fromDeviceId: String? = nil
    ) async throws {
        var args: [String: ConvexEncodable?] = [
            "callId": callId,
            "fromUserId": fromUserId,
            "toUserId": toUserId,
            "kind": kind.rawValue,
            "payload": payload,
        ]
        if let targetDeviceId { args["targetDeviceId"] = targetDeviceId }
        if let fromDeviceId { args["fromDeviceId"] = fromDeviceId }
        try await convex.mutationVoid("calls:sendSignal", with: args)
    }

    func consumeSignal(signalId: String, userId: String) async throws {
        try await convex.mutationVoid("calls:consumeSignal", with: ["signalId": signalId, "userId": userId])
    }

    func signalsForUser(userId: String) async throws -> [CallSignal] {
        let docs: [ConvexCallSignalDoc] = try await convex.queryOnce("calls:signalsForUser", with: ["userId": userId])
        return docs.map { $0.toCallSignal() }
    }

    func activeCall(userId: String) async throws -> Call? {
        let doc: ConvexActiveCallDoc? = try await convex.queryOnce("calls:activeCallForUser", with: ["userId": userId])
        return doc?.toCall()
    }

    // MARK: ICE / TURN

    func iceConfig(userId: String) async throws -> [IceServerConfig] {
        let doc: ConvexIceConfigDoc = try await convex.action("calls:getIceConfig", with: ["userId": userId])
        return doc.iceServers.map { IceServerConfig(urls: [$0.urls], username: $0.username, credential: $0.credential) }
    }

    // MARK: VoIP token registration

    func setVoipToken(userId: String, token: String) async throws {
        try await convex.mutationVoid("voipTokens:setVoipToken", with: [
            "userId": userId,
            "deviceId": DeviceIdentityManager.deviceId,
            "platform": DeviceIdentityManager.platform,
            "token": token,
            "deviceName": DeviceIdentityManager.deviceName,
        ])
    }

    func setFcmToken(userId: String, token: String) async throws {
        try await convex.mutationVoid("voipTokens:setFcmToken", with: [
            "userId": userId,
            "deviceId": DeviceIdentityManager.deviceId,
            "platform": DeviceIdentityManager.platform,
            "token": token,
            "deviceName": DeviceIdentityManager.deviceName,
        ])
    }

    /// Registers this device without a push token (e.g. macOS/simulator) so it
    /// still appears in the multi-device handoff list.
    func registerDevice(userId: String) async throws {
        try await convex.mutationVoid("voipTokens:registerDevice", with: [
            "userId": userId,
            "deviceId": DeviceIdentityManager.deviceId,
            "platform": DeviceIdentityManager.platform,
            "deviceName": DeviceIdentityManager.deviceName,
        ])
    }

    func clearDeviceToken(userId: String) async throws {
        try await convex.mutationVoid("voipTokens:clearDeviceToken", with: [
            "userId": userId,
            "deviceId": DeviceIdentityManager.deviceId,
        ])
    }
}
