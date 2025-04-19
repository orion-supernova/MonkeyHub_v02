import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)

            Text("Initializing...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    LoadingView()
}
