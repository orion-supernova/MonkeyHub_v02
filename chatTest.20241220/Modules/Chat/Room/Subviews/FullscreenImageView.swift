import SwiftUI

struct FullscreenImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var backgroundOpacity: Double = 0
    @State private var imageScale: CGFloat = 0.8
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Animated background
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissWithAnimation()
                    }

                // Image with zoom animation
                ZoomableScrollView {
                    if url.isFileURL {
                        if let uiImage = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(imageScale)
                                .offset(dragOffset)
                                .gesture(dismissDragGesture)
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.white)
                        }
                    } else {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(imageScale)
                                .offset(dragOffset)
                                .gesture(dismissDragGesture)
                        } placeholder: {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                backgroundOpacity = 1
                imageScale = 1
            }
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                // Fade background based on drag distance
                let progress = min(abs(value.translation.height) / 300, 1)
                backgroundOpacity = 1 - (progress * 0.5)
                imageScale = 1 - (progress * 0.15)
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                if abs(value.translation.height) > threshold || abs(value.predictedEndTranslation.height) > threshold * 2 {
                    dismissWithAnimation()
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = .zero
                        backgroundOpacity = 1
                        imageScale = 1
                    }
                }
            }
    }

    private func dismissWithAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            backgroundOpacity = 0
            imageScale = 0.8
            dragOffset = .zero
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dismiss()
        }
    }
}
