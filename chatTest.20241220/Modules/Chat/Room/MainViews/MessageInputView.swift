import SwiftUI

struct MessageInputView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var messageText: String
    @Binding var showImagePicker: Bool
    @Binding var isShowingAttachmentMenu: Bool
    
    let onSendMessage: (String) async -> Void
    let onTextChanged: (String) -> Void
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
            
#if os(macOS)
            EnterToSendTextView(text: $messageText, onTextChanged: onTextChanged) { textToSend in
                Task {
                    await onSendMessage(textToSend)
                }
            }
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.3))
            )
#else
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onChange(of: messageText) { oldValue, newValue in
                    onTextChanged(newValue)
                }
#endif
            
            Button {
                Task { await sendIfNotEmpty() }
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
        .overlay(Divider(), alignment: .top)
    }
    
    private func sendIfNotEmpty() async {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let textToSend = messageText
        messageText = ""
        onTextChanged("")

        await onSendMessage(textToSend)
    }
}

#if os(macOS)
import SwiftUI

struct EnterToSendTextView: NSViewRepresentable {
    @Binding var text: String
    let onTextChanged: (String) -> Void
    let onSend: (String) -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)

        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 6, height: 4)

        textView.drawsBackground = false
        textView.backgroundColor = .clear

        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        guard nsView.window?.firstResponder !== nsView else { return }
        if nsView.string != text {
            nsView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: EnterToSendTextView

        init(_ parent: EnterToSendTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onTextChanged(tv.string)
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let textToSend = textView.string

                textView.window?.makeFirstResponder(nil)
                parent.text = ""
                parent.onTextChanged("")
                parent.onSend(textToSend)

                DispatchQueue.main.async {
                    textView.window?.makeFirstResponder(textView)
                }

                return true
            }
            return false
        }
    }
}
#endif