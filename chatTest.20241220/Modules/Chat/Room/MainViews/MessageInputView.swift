import SwiftUI

struct MessageInputView: View {
    @Binding var messageText: String
    @Binding var showImagePicker: Bool
    @Binding var isShowingAttachmentOptions: Bool
    let onSendMessage: () async -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isShowingAttachmentOptions.toggle()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .confirmationDialog("Add Attachment", isPresented: $isShowingAttachmentOptions) {
                Button("Photo") {
                    showImagePicker = true
                }
                Button("Cancel", role: .cancel) {}
            }

            TextField("Message", text: $messageText)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    await onSendMessage()
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .overlay(
            Divider(),
            alignment: .top
        )
    }
}
