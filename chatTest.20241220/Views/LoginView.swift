import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var cloudKit: CloudKitManager
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isAnimating = false
    @State private var showContent = false
    @State private var bubblePhase = 0.0
    @StateObject private var viewModel = LoginViewModel()

    // Refined deep ocean colors
    private let oceanColors: [Color] = [
        Color(red: 0.016, green: 0.051, blue: 0.129),  // Deep ocean
        Color(red: 0.019, green: 0.106, blue: 0.247),  // Midnight blue
        Color(red: 0.039, green: 0.180, blue: 0.360),  // Ocean blue
    ]

    var body: some View {
        ZStack {
            // Background layers
            GeometryReader { geometry in
                // Base gradient
                LinearGradient(colors: oceanColors, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                // Simplified light rays
                LightRaysView()
                    .opacity(isAnimating ? 0.06 : 0)

                // Essential bubble streams
                BubbleStreamView(phase: bubblePhase)
                    .opacity(isAnimating ? 0.4 : 0)
            }

            // Content
            VStack(spacing: 45) {
                Spacer()

                // App icon
                AppIconView(isAnimating: isAnimating)
                    .offset(y: showContent ? 0 : 50)
                    .opacity(showContent ? 1 : 0)

                // Welcome text
                VStack(spacing: 16) {
                    Text("Welcome to Chat")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                    Text("Sign in with your Apple ID to start chatting")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .offset(y: showContent ? 0 : 30)
                .opacity(showContent ? 1 : 0)

                Spacer()

                // Sign in button
                VStack {
                    if viewModel.isAuthenticated {
                        Button(action: viewModel.signOut) {
                            Text("Sign Out")
                                .foregroundColor(.white)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 30)
                    } else {
                        SignInWithAppleButton { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            viewModel.handleSignInWithApple(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.2), radius: 15)
                        .padding(.horizontal, 30)
                    }
                }
                .offset(y: showContent ? 0 : 40)
                .opacity(showContent ? 1 : 0)
            }
            .padding(.vertical, 60)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: startAnimations)
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $viewModel.showSuccess) {
            Button("OK") {}
        } message: {
            Text(viewModel.successMessage)
        }
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 1.5)) {
            showContent = true
        }
        withAnimation(.easeInOut(duration: 2)) {
            isAnimating = true
        }
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
            bubblePhase = 1.0
        }
    }
}

// Simplified supporting views
struct LightRaysView: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<4) { i in
                let rotation = Double(i) * 45.0 + (animate ? 15 : 0)
                RayShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.15),
                                .white.opacity(0.05),
                                .clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: geometry.size.width * 1.5)
                    .rotationEffect(.degrees(rotation))
                    .offset(y: -geometry.size.height * 0.3)
                    .blur(radius: 15)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

struct RayShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct BubbleStreamView: View {
    let phase: Double

    var body: some View {
        GeometryReader { geometry in
            // Multiple layers of bubbles for depth
            ForEach(0..<6) { layer in  // Increased from 4 to 6 layers
                BubbleColumn(
                    phase: phase,
                    columnOffset: CGFloat(layer),
                    geometrySize: geometry.size,
                    depth: Double(layer) / 6.0
                )
            }

            // Add some random floating bubbles
            ForEach(0..<8) { _ in
                FloatingBubble2(
                    phase: phase,
                    geometrySize: geometry.size
                )
            }
        }
    }
}

// New view for random floating bubbles
struct FloatingBubble2: View {
    let phase: Double
    let geometrySize: CGSize
    let initialPosition: CGPoint
    let speed: Double
    let size: CGFloat

    init(phase: Double, geometrySize: CGSize) {
        self.phase = phase
        self.geometrySize = geometrySize
        self.initialPosition = CGPoint(
            x: CGFloat.random(in: 0...geometrySize.width),
            y: CGFloat.random(in: 0...geometrySize.height)
        )
        self.speed = Double.random(in: 0.3...0.7)
        self.size = CGFloat.random(in: 2...5)
    }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .white.opacity(0.6),
                        .white.opacity(0.3),
                        .white.opacity(0.1),
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 4
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 0.3)
            .offset(
                x: initialPosition.x + sin(phase * .pi * speed) * 20,
                y: initialPosition.y
                    - (phase * geometrySize.height * speed)
                    .remainder(dividingBy: geometrySize.height * 1.2)
            )
            .opacity(0.4)
    }
}

struct BubbleColumn: View {
    let phase: Double
    let columnOffset: CGFloat
    let geometrySize: CGSize
    let depth: Double

    var body: some View {
        let bubbleCount = Int.random(in: 5...10)  // Increased range

        ForEach(0..<bubbleCount, id: \.self) { index in
            let baseX = geometrySize.width * (0.1 + columnOffset * 0.2)
            let delayedPhase = phase - Double(index) * 0.15
            let yOffset = geometrySize.height * (1.2 - delayedPhase.remainder(dividingBy: 1))

            // Enhanced natural movement
            let wobbleFrequency = Double.random(in: 1.5...3.0)
            let wobbleAmplitude = Double.random(in: 15...30) * (1 - depth)
            let xOffset = sin(delayedPhase * .pi * wobbleFrequency) * wobbleAmplitude

            // Main bubble
            BubbleShape(wobblePhase: delayedPhase)
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.7 * (1 - depth)),
                            .white.opacity(0.3 * (1 - depth)),
                            .white.opacity(0.1 * (1 - depth)),
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 8 * (1 - depth)
                    )
                )
                .frame(
                    width: CGFloat.random(in: 3...8) * (1 - depth) + 2,
                    height: CGFloat.random(in: 3...8) * (1 - depth) + 2
                )
                .blur(radius: depth * 0.5)
                .offset(
                    x: baseX + xOffset,
                    y: yOffset
                )
                .opacity(
                    delayedPhase.remainder(dividingBy: 1) < 0.1
                        ? 0 : delayedPhase.remainder(dividingBy: 1) > 0.9 ? 0 : 0.8
                )
                .scaleEffect(sin(delayedPhase * .pi * 2) * 0.1 + 0.9)
                .rotationEffect(.degrees(sin(delayedPhase * .pi) * 20))
        }
    }
}

// New shape for more organic bubbles
struct BubbleShape: Shape {
    let wobblePhase: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // Create slightly wobbling circle
        let points = 8
        for i in 0..<points {
            let angle = (Double(i) / Double(points)) * .pi * 2
            let wobbleAmount = sin(wobblePhase * 2 + angle) * radius * 0.1
            let pointRadius = radius + wobbleAmount
            let x = center.x + cos(angle) * pointRadius
            let y = center.y + sin(angle) * pointRadius

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        path.closeSubpath()
        return path
    }
}

struct AppIconView: View {
    let isAnimating: Bool
    @State private var iconPhase = 0.0

    var body: some View {
        Circle()
            .fill(
                .linearGradient(
                    colors: [
                        .white.opacity(0.2),
                        .white.opacity(0.1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 120, height: 120)
            .overlay {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 45, weight: .light))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.white, .white.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .symbolEffect(
                        .bounce.up.byLayer,
                        options: .speed(0.7),
                        value: iconPhase
                    )
            }
            .shadow(color: .black.opacity(0.3), radius: 20)
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                    iconPhase += 1
                }
            }
    }
}

// Color Extension remains the same...

#Preview {
    LoginView()
}
