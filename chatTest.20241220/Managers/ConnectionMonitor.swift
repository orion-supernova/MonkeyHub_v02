import Foundation
import Network
import Combine

/// Observes network reachability so the UI can show an offline/reconnecting
/// banner (the ConvexMobile SDK doesn't expose socket state directly, so we
/// surface device connectivity, which is what users care about).
@MainActor
final class ConnectionMonitor: ObservableObject {
    static let shared = ConnectionMonitor()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "monkeyhub.network.monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if self.isOnline != online {
                    withAnimationIfNeeded { self.isOnline = online }
                }
            }
        }
        monitor.start(queue: queue)
    }
}

private func withAnimationIfNeeded(_ body: () -> Void) { body() }
