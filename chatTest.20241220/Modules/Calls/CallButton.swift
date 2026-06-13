import SwiftUI

/// A phone button that offers audio/video and places a call to `peer` within `roomId`.
struct CallButton: View {
    let peer: ChatUser
    let roomId: String
    var tint: Color = .green

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            Image(systemName: "phone.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .confirmationDialog("Call \(peer.displayName)", isPresented: $showPicker, titleVisibility: .visible) {
            Button("Voice Call") {
                Task { await CallController.shared.placeCall(peer: peer, roomId: roomId, type: .audio) }
            }
            Button("Video Call") {
                Task { await CallController.shared.placeCall(peer: peer, roomId: roomId, type: .video) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
