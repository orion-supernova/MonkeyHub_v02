import SwiftUI

struct ICloudErrorView: View {
    let message: String

    @EnvironmentObject private var cloudKitManager: CloudKitManager
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Animated circles in background
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: geometry.size.width * 0.8)
                    .offset(x: -geometry.size.width * 0.3, y: -geometry.size.height * 0.2)
                    .blur(radius: 20)
                    .scaleEffect(isAnimating ? 1.2 : 0.8)

                Circle()
                    .fill(.purple.opacity(0.1))
                    .frame(width: geometry.size.width * 0.8)
                    .offset(x: geometry.size.width * 0.3, y: geometry.size.height * 0.2)
                    .blur(radius: 20)
                    .scaleEffect(isAnimating ? 0.8 : 1.2)

                // Main content
                VStack(spacing: 30) {
                    Spacer()

                    // Icon with pulsing animation
                    ZStack {
                        Circle()
                            .fill(.red.opacity(0.1))
                            .frame(width: 120, height: 120)
                            .scaleEffect(isAnimating ? 1.2 : 0.8)

                        Image(systemName: "icloud.slash")
                            .font(.system(size: 50))
                            .foregroundStyle(.red)
                            .symbolEffect(.bounce, options: .repeating, value: isAnimating)
                    }

                    VStack(spacing: 16) {
                        Text("iCloud Required")
                            .font(.title)
                            .bold()

                        Text(message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    // Settings button with glass effect
                    Button(action: openSettings) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                            Text("Open Settings")
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(.white.opacity(0.2))
                        }
                    }
                    .tint(.primary)
                    .padding(.horizontal)

                    // Retry button
                    Button {
                        Task {
                            await cloudKitManager.initialize()
                        }
                    } label: {
                        Text("Try Again")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .padding()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever()) {
                isAnimating = true
            }
        }
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: "App-prefs:") {
            UIApplication.shared.open(settingsUrl)
        }

    }
}

#Preview {
    ICloudErrorView(message: "Please sign in to iCloud in Settings to use this app")
}
