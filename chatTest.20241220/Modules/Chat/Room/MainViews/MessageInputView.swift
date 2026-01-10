import SwiftUI

struct MessageInputView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Binding var messageText: String
    @Binding var showImagePicker: Bool
    @Binding var isShowingAttachmentMenu: Bool
    let onSendMessage: () async -> Void
    let onTakePhoto: () -> Void
    let onTakeVideo: () -> Void
    let onRecordAudio: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isShowingAttachmentMenu.toggle()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .foregroundStyle(LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }

            TextField("Message", text: $messageText)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    await onSendMessage()
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(Color.platformBackground)
        .overlay(
            Divider(),
            alignment: .top
        )
    }
}
