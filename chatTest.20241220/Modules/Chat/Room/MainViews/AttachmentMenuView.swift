import SwiftUI

struct AttachmentMenuView: View {
    @Binding var isPresented: Bool
    let onTakePhoto: () -> Void
    let onTakeVideo: () -> Void
    let onRecordAudio: () -> Void
    let onChooseFromGallery: () -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Add Media")
                .font(.title2.bold())
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                .padding(.horizontal)

            HStack(spacing: 20) {
                AttachmentButton(icon: "camera.fill", text: "Camera", action: onTakePhoto)
                AttachmentButton(icon: "video.fill", text: "Video", action: onTakeVideo)
                AttachmentButton(icon: "mic.fill", text: "Audio", action: onRecordAudio)
                AttachmentButton(icon: "photo.on.rectangle", text: "Gallery", action: onChooseFromGallery)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 30)
        .background(selectedTheme.colors(for: colorScheme).background)
        .cornerRadius(20)
    }
}

struct AttachmentButton: View {
    let icon: String
    let text: String
    let action: () -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                    .frame(width: 60, height: 60)
                    .background(
                        LinearGradient(
                            colors: selectedTheme.colors(for: colorScheme).primary,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())

                Text(text)
                    .font(.caption)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}
