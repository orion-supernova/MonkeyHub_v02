import SwiftUI

struct LoginView: View {
    @State private var isAnimating = false
    @State private var showContent = false
    @State private var bubblePhase = 0.0
    @State private var isSignUp = false
    @State private var username = ""
    @State private var password = ""
    @State private var name = ""
    @State private var email = ""
    @StateObject private var viewModel = LoginViewModel()

    private let oceanColors: [Color] = [
        Color(red: 0.016, green: 0.051, blue: 0.129),
        Color(red: 0.019, green: 0.106, blue: 0.247),
        Color(red: 0.039, green: 0.180, blue: 0.360),
    ]

    var body: some View {
        ZStack {
            GeometryReader { _ in
                LinearGradient(colors: oceanColors, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                LightRaysView()
                    .opacity(isAnimating ? 0.06 : 0)
                BubbleStreamView(phase: bubblePhase)
                    .opacity(isAnimating ? 0.4 : 0)
            }

            VStack(spacing: 30) {
                Spacer()

                AppIconView(isAnimating: isAnimating)
                    .offset(y: showContent ? 0 : 50)
                    .opacity(showContent ? 1 : 0)

                VStack(spacing: 8) {
                    Text("Welcome to Chat")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                    Text(isSignUp ? "Create your account" : "Sign in to continue")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .offset(y: showContent ? 0 : 30)
                .opacity(showContent ? 1 : 0)

                Spacer()

                VStack(spacing: 14) {
                    if isSignUp {
                        OceanTextField(text: $name, placeholder: "Full Name", icon: "person")
                        OceanTextField(text: $email, placeholder: "Email (optional)", icon: "envelope")
                    }
                    OceanTextField(text: $username, placeholder: "Username", icon: "at")
                    OceanSecureField(text: $password, placeholder: "Password", icon: "lock")

                    if let err = viewModel.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }

                    Button(action: {
                        if isSignUp {
                            viewModel.signUp(username: username, password: password, name: name, email: email)
                        } else {
                            viewModel.signIn(username: username, password: password)
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        } else {
                            Text(isSignUp ? "Create Account" : "Sign In")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                        }
                    }
                    .background(.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.2), radius: 15)

                    Button(action: {
                        withAnimation {
                            isSignUp.toggle()
                            viewModel.errorMessage = nil
                        }
                    }) {
                        Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 30)
                .offset(y: showContent ? 0 : 40)
                .opacity(showContent ? 1 : 0)
            }
            .padding(.vertical, 60)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: startAnimations)
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 1.5)) { showContent = true }
        withAnimation(.easeInOut(duration: 2)) { isAnimating = true }
        withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) { bubblePhase = 1.0 }
    }
}

// MARK: - Ocean Text Field Styles

private struct OceanTextField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.5)))
                .foregroundStyle(.white)
                .autocapitalization(.none)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct OceanSecureField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.5)))
                .foregroundStyle(.white)
        }
        .padding(14)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Ocean Animation Views

struct LightRaysView: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<4) { i in
                let rotation = Double(i) * 45.0 + (animate ? 15 : 0)
                RayShape()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.15), .white.opacity(0.05), .clear],
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
            ForEach(0..<6) { layer in
                BubbleColumn(
                    phase: phase,
                    columnOffset: CGFloat(layer),
                    geometrySize: geometry.size,
                    depth: Double(layer) / 6.0
                )
            }
            ForEach(0..<8) { _ in
                FloatingBubble2(phase: phase, geometrySize: geometry.size)
            }
        }
    }
}

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
                    colors: [.white.opacity(0.6), .white.opacity(0.3), .white.opacity(0.1)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 4
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 0.3)
            .offset(
                x: initialPosition.x + sin(phase * .pi * speed) * 20,
                y: initialPosition.y - (phase * geometrySize.height * speed)
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
        let bubbleCount = Int.random(in: 5...10)
        ForEach(0..<bubbleCount, id: \.self) { index in
            let baseX = geometrySize.width * (0.1 + columnOffset * 0.2)
            let delayedPhase = phase - Double(index) * 0.15
            let yOffset = geometrySize.height * (1.2 - delayedPhase.remainder(dividingBy: 1))
            let wobbleFrequency = Double.random(in: 1.5...3.0)
            let wobbleAmplitude = Double.random(in: 15...30) * (1 - depth)
            let xOffset = sin(delayedPhase * .pi * wobbleFrequency) * wobbleAmplitude

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
                .offset(x: baseX + xOffset, y: yOffset)
                .opacity(
                    delayedPhase.remainder(dividingBy: 1) < 0.1 ? 0 :
                    delayedPhase.remainder(dividingBy: 1) > 0.9 ? 0 : 0.8
                )
                .scaleEffect(sin(delayedPhase * .pi * 2) * 0.1 + 0.9)
                .rotationEffect(.degrees(sin(delayedPhase * .pi) * 20))
        }
    }
}

struct BubbleShape: Shape {
    let wobblePhase: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let points = 8
        for i in 0..<points {
            let angle = (Double(i) / Double(points)) * .pi * 2
            let wobbleAmount = sin(wobblePhase * 2 + angle) * radius * 0.1
            let pointRadius = radius + wobbleAmount
            let x = center.x + cos(angle) * pointRadius
            let y = center.y + sin(angle) * pointRadius
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
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
                    colors: [.white.opacity(0.2), .white.opacity(0.1)],
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
                    .symbolEffect(.bounce.up.byLayer, options: .speed(0.7), value: iconPhase)
            }
            .shadow(color: .black.opacity(0.3), radius: 20)
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                    iconPhase += 1
                }
            }
    }
}

#Preview {
    LoginView()
}
