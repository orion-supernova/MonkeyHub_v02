import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Stable per-device identity used for VoIP push-token registration and
/// multi-device call handoff. The `deviceId` is a UUID generated once and
/// persisted in the Keychain so it survives app reinstalls (matching the
/// session-id strategy in `ConvexAuthService`).
enum DeviceIdentityManager {
    private static let deviceIdKey = "monkeyhub_device_id"

    /// Persistent UUIDv4 for this install. Generated and stored on first access.
    static var deviceId: String {
        if let existing = KeychainService.get(deviceIdKey) {
            return existing
        }
        let fresh = UUID().uuidString
        KeychainService.save(fresh, for: deviceIdKey)
        return fresh
    }

    /// Platform string expected by `voipTokens:*` mutations.
    static var platform: String {
        #if os(macOS)
        return "macos"
        #elseif targetEnvironment(simulator)
        return "ios-simulator"
        #elseif os(visionOS)
        return "visionos"
        #else
        return "ios"
        #endif
    }

    /// Human-readable label shown in the "Move call here" pill.
    static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Device"
        #endif
    }
}
