import SwiftUI

struct LoadingView: View {
    @State private var isAnimating = false
    @State private var showText = false
    @State private var rotationAngle = 0.0
    @State private var pulseScale = 1.0

    private let gradientColors: [Color] = [.blue, .purple, .indigo]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Animated background
                AngularGradient(
                    colors: gradientColors,
                    center: .center,
                    angle: .degrees(rotationAngle)
                )
                .blur(radius: 70)
                .ignoresSafeArea()

                // Floating particles
                ForEach(0..<12) { index in
                    Circle()
                        .fill(gradientColors[index % gradientColors.count])
                        .frame(width: CGFloat.random(in: 4...12))
                        .offset(
                            x: CGFloat.random(
                                in: -geometry.size.width / 2...geometry.size.width / 2),
                            y: CGFloat.random(
                                in: -geometry.size.height / 2...geometry.size.height / 2)
                        )
                        .blur(radius: 3)
                        .opacity(isAnimating ? 0.3 : 0)
                        .animation(
                            .easeInOut(duration: Double.random(in: 2...4))
                                .repeatForever()
                                .delay(Double.random(in: 0...2)),
                            value: isAnimating
                        )
                }

                // Main content
                VStack(spacing: 40) {
                    // Loading spinner
                    ZStack {
                        // Outer ring
                        Circle()
                            .stroke(
                                .linearGradient(
                                    colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 8
                            )
                            .frame(width: 80, height: 80)

                        // Spinning gradient arc
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(
                                .linearGradient(
                                    colors: gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(
                                    lineWidth: 8,
                                    lineCap: .round
                                )
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(isAnimating ? 360 : 0))
                            .animation(
                                .linear(duration: 1)
                                    .repeatForever(autoreverses: false),
                                value: isAnimating
                            )

                        // Center dot
                        Circle()
                            .fill(
                                .linearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 15, height: 15)
                            .scaleEffect(pulseScale)
                    }
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 100, height: 100)
                            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                    }

                    // Text
                    VStack(spacing: 12) {
                        Text("Initializing")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.primary, .primary.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text("Please wait while we set things up...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(showText ? 1 : 0)
                    .offset(y: showText ? 0 : 20)
                }
                .padding()
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever()) {
                pulseScale = 0.8
            }
            withAnimation(.easeOut(duration: 0.8)) {
                showText = true
            }
            isAnimating = true
        }
    }
}

#Preview {
    LoadingView()
        .preferredColorScheme(.dark)
}
