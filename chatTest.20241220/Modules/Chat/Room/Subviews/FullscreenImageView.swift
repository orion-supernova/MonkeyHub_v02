import SwiftUI

struct FullscreenImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ZoomableScrollView {
                if url.isFileURL {
                    if let uiImage = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
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
            .ignoresSafeArea()
        }
        .onTapGesture {
            dismiss()
        }
    }
}
