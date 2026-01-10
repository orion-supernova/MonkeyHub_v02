import SwiftUI

struct ICloudErrorView: View {
    let message: String

    @EnvironmentObject private var cloudKitManager: CloudKitManager
    @State private var isAnimating = false
    @State private var showContent = false
    @State private var isRetrying = false
    @State private var rotationAngle: Double = 0
    @State private var hoverEffect = false

    // Animation properties
    private let gradientColors: [Color] = [.blue, .purple, .indigo]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Animated gradient background
                AngularGradient(
                    colors: gradientColors,
                    center: .center,
                    angle: .degrees(rotationAngle)
                )
                .blur(radius: 70)
                .ignoresSafeArea()

                // Floating bubbles
                ForEach(0..<8) { index in
                    FloatingBubble(
                        size: CGFloat.random(in: 100...200),
                        offset: CGPoint(
                            x: CGFloat.random(
                                in: -geometry.size.width / 2...geometry.size.width / 2),
                            y: CGFloat.random(
                                in: -geometry.size.height / 2...geometry.size.height / 2)
                        ),
                        color: gradientColors[index % gradientColors.count]
                    )
                }

                // Content container with glass effect
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(
                                .linearGradient(
                                    colors: [.white.opacity(0.5), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                    .padding(30)
                    .opacity(showContent ? 1 : 0)
                    .scaleEffect(showContent ? 1 : 0.9)

                // Main content
                VStack(spacing: 35) {
                    Spacer()

                    // Animated iCloud icon
                    ZStack {
                        // Pulse effect
                        ForEach(0..<3) { i in
                            Circle()
                                .stroke(Color.red.opacity(0.3), lineWidth: 2)
                                .frame(width: 130, height: 130)
                                .scaleEffect(isAnimating ? 1.6 : 0.8)
                                .opacity(isAnimating ? 0 : 0.5)
                                .animation(
                                    .easeInOut(duration: 2.5)
                                        .repeatForever()
                                        .delay(Double(i) * 0.4),
                                    value: isAnimating
                                )
                        }

                        // Icon container
                        Circle()
                            .fill(
                                .linearGradient(
                                    colors: [.red.opacity(0.2), .red.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            }
                            .shadow(color: .red.opacity(0.3), radius: 15, y: 5)

                        Image(systemName: "icloud.slash")
                            .font(.system(size: 45, weight: .light))
                            .foregroundStyle(.red)
                            .symbolEffect(
                                .bounce.down.byLayer,
                                options: .speed(0.5),
                                value: isRetrying
                            )
                            .rotation3DEffect(
                                .degrees(hoverEffect ? 5 : -5), axis: (x: 1, y: 0, z: 0)
                            )
                            .animation(.easeInOut(duration: 2).repeatForever(), value: hoverEffect)
                    }
                    .offset(y: showContent ? 0 : 50)
                    .opacity(showContent ? 1 : 0)

                    // Text content
                    VStack(spacing: 16) {
                        Text("iCloud Required")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.primary, .primary.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text(message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .offset(y: showContent ? 0 : 30)
                    .opacity(showContent ? 1 : 0)

                    Spacer()

                    // Action buttons
                    VStack(spacing: 16) {
                        // Settings button
                        Button(action: openSettings) {
                            HStack(spacing: 12) {
                                Image(systemName: "gearshape.fill")
                                    .imageScale(.large)
                                Text("Open Settings")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(
                                        .linearGradient(
                                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                .linearGradient(
                                                    colors: [.white.opacity(0.5), .clear],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    }
                            }
                            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                        }
                        .buttonStyle(ScaleButtonStyle())

                        // Retry button
                        Button {
                            withAnimation(.spring()) {
                                isRetrying = true
                            }
                            Task {
                                await cloudKitManager.initialize()
                                isRetrying = false
                            }
                        } label: {
                            Text("Try Again")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(.horizontal)
                    .offset(y: showContent ? 0 : 50)
                    .opacity(showContent ? 1 : 0)
                }
                .padding(40)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                showContent = true
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            isAnimating = true
            hoverEffect = true
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let settingsUrl = URL(string: "App-prefs:") {
            UIApplication.shared.open(settingsUrl)
        }
        #elseif canImport(AppKit)
        if let settingsUrl = URL(string: "x-apple.systempreferences:com.apple.preferences.icloud") {
            NSWorkspace.shared.open(settingsUrl)
        }
        #endif
    }
}

// MARK: - Supporting Views and Styles
struct FloatingBubble: View {
    let size: CGFloat
    let offset: CGPoint
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(color.opacity(0.1))
            .frame(width: size)
            .offset(x: offset.x, y: offset.y)
            .blur(radius: 50)
            .opacity(isAnimating ? 0.8 : 0.3)
            .animation(
                .easeInOut(duration: Double.random(in: 4...6))
                    .repeatForever()
                    .delay(Double.random(in: 0...2)),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(), value: configuration.isPressed)
    }
}

#Preview {
    ICloudErrorView(message: "Please sign in to iCloud in Settings to use this app")
        .preferredColorScheme(.dark)
}
