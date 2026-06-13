import SwiftUI

/// Slim banner shown at the top when the device loses connectivity.
struct ConnectionBanner: View {
    @ObservedObject private var monitor = ConnectionMonitor.shared

    var body: some View {
        if !monitor.isOnline {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 13, weight: .semibold))
                Text("No internet connection")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.orange)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
