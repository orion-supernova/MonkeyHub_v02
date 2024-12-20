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
                SignInWithAppleButton { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleSignIn(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.2), radius: 15)
                .padding(.horizontal, 30)
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

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        Task {
            do {
                switch result {
                case .success(let authorization):
                    if let appleIDCredential = authorization.credential
                        as? ASAuthorizationAppleIDCredential
                    {
                        try await cloudKit.signIn(with: appleIDCredential)
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
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
            ForEach(0..<3) { column in
                BubbleColumn(
                    phase: phase,
                    columnOffset: CGFloat(column),
                    geometrySize: geometry.size
                )
            }
        }
    }
}

struct BubbleColumn: View {
    let phase: Double
    let columnOffset: CGFloat
    let geometrySize: CGSize

    var body: some View {
        let bubbleCount = 6

        ForEach(0..<bubbleCount, id: \.self) { index in
            let baseX = geometrySize.width * (0.2 + columnOffset * 0.3)
            let delayedPhase = phase - Double(index) * 0.1
            let yOffset = geometrySize.height * (1.2 - delayedPhase.remainder(dividingBy: 1))

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.5),
                            .white.opacity(0.2),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: CGFloat.random(in: 4...8))
                .blur(radius: 0.5)
                .offset(
                    x: baseX + sin(delayedPhase * .pi * 2) * 20,
                    y: yOffset
                )
                .opacity(
                    delayedPhase.remainder(dividingBy: 1) < 0.1
                        ? 0 : delayedPhase.remainder(dividingBy: 1) > 0.9 ? 0 : 0.6
                )
        }
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
