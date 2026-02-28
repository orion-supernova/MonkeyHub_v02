import SwiftUI

struct FullscreenImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var backgroundOpacity: Double = 0
    @State private var dragOffset: CGSize = .zero
    @State private var currentZoomScale: CGFloat = 1.0
    @State private var loadedFileImage: PlatformImage?
    @State private var isLoadingFileImage = false

    var body: some View {
        ZStack {
            // Animated background
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    if isAtBaseZoom {
                        dismiss()
                    }
                }

            // Image with scroll-view zoom. Keep this transform-free to avoid gesture conflicts.
            ZoomableScrollView(onZoomScaleChanged: { scale in
                currentZoomScale = scale
            }) {
                imageContent
            }
            .ignoresSafeArea()
            .offset(dragOffset)
            .simultaneousGesture(dismissDragGesture)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                backgroundOpacity = 1
            }
        }
        .task(id: url) {
            guard url.isFileURL else { return }
            loadedFileImage = ImageLoaderManager.shared.getCachedImage(for: url)
            if loadedFileImage != nil { return }
            isLoadingFileImage = true
            loadedFileImage = PlatformImage.fromFile(url.path)
            isLoadingFileImage = false
        }
    }

    private var isAtBaseZoom: Bool {
        currentZoomScale <= 1.02
    }

    @ViewBuilder
    private var imageContent: some View {
        if url.isFileURL {
            if let platformImage = loadedFileImage {
                Image(platformImage: platformImage)
                    .resizable()
                    .scaledToFit()
            } else if isLoadingFileImage {
                ProgressView()
                    .tint(.white)
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
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard isAtBaseZoom else { return }
                dragOffset = value.translation
                // Fade background based on drag distance
                let progress = min(abs(value.translation.height) / 300, 1)
                backgroundOpacity = 1 - (progress * 0.5)
            }
            .onEnded { value in
                guard isAtBaseZoom else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = .zero
                        backgroundOpacity = 1
                    }
                    return
                }

                let threshold: CGFloat = 100
                if abs(value.translation.height) > threshold || abs(value.predictedEndTranslation.height) > threshold * 2 {
                    dismiss()
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = .zero
                        backgroundOpacity = 1
                    }
                }
            }
    }
}
