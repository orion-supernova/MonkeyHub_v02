import SwiftUI

struct MessageInputView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFieldFocused: Bool
    
    @Binding var messageText: String
    @Binding var showImagePicker: Bool
    @Binding var isShowingAttachmentMenu: Bool
    
    var navHighlight: Int? = nil

    let onSendMessage: (String) async -> Void
    let onTextChanged: (String) -> Void
    let onTakePhoto: () -> Void
    let onTakeVideo: () -> Void
    let onRecordAudio: () -> Void
    
    var body: some View {
        // This HStack is the ONLY container. No .background means it's invisible except for the glass components.
        HStack(spacing: 12) {
            LiquidButton(icon: "plus", showFocusRing: navHighlight == 3) {
                // Let the system handle keyboard dismiss with animation
                #if canImport(UIKit)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
                isShowingAttachmentMenu.toggle()
            }
            
            GlassTextField(
                text: $messageText,
                isTextFieldFocused: $isTextFieldFocused,
                showFocusRing: navHighlight == 4,
                onTextChanged: onTextChanged,
                onSend: { Task { await sendIfNotEmpty() } }
            )
            
            LiquidButton(
                icon: "arrow.up",
                isDisabled: messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                showFocusRing: navHighlight == 5
            ) {
                Task { await sendIfNotEmpty() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Ensure the input area stays above the keyboard automatically
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

// MARK: - Components

struct LiquidButton: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    var isDisabled: Bool = false
    var showFocusRing: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(
                    isDisabled
                    ? AnyShapeStyle(Color.gray.opacity(0.4))
                    : AnyShapeStyle(LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                      ))
                )
                .frame(width: 44, height: 44)
#if os(macOS)
                .background(
                    Circle().fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle().stroke(LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.5 : 0.8),
                            .white.opacity(0.2),
                            .black.opacity(colorScheme == .dark ? 0 : 0.05)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1.5)
                )
#else
                .modifier(LiquidGlassModifier(cornerRadius: 22))
#endif
                .contentShape(Circle())
        }
#if os(macOS)
        .buttonStyle(.plain)
        .focusable(false)
        .overlay(
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.5
                )
                .frame(width: 48, height: 48)
                .opacity(showFocusRing ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: showFocusRing)
        )
#else
        .buttonStyle(LiquidButtonStyle())
#endif
        .disabled(isDisabled)
    }
}

struct GlassTextField: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    @FocusState.Binding var isTextFieldFocused: Bool
    var showFocusRing: Bool = false
    let onTextChanged: (String) -> Void
    let onSend: () -> Void
    
    var body: some View {
        Group {
#if os(macOS)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Message")
                        .padding(.horizontal, 16)
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
                EnterToSendTextView(text: $text, onTextChanged: onTextChanged, onSend: { _ in onSend() })
                .frame(height: 24)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .modifier(LiquidGlassModifier(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: selectedTheme.colors(for: colorScheme).primary,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .opacity(showFocusRing ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: showFocusRing)
            )
#else
            TextField("Message", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isTextFieldFocused)
                .submitLabel(.send)
                .onSubmit { onSend() }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .modifier(LiquidGlassModifier(cornerRadius: 22))
                .onChange(of: text) { oldValue, newValue in
                    // If the user hits Return, send the message and strip the newline
                    if newValue.contains("\n") {
                        let trimmed = newValue.replacingOccurrences(of: "\n", with: "")
                        text = trimmed
                        onTextChanged(trimmed)
                        onSend()
                    } else {
                        onTextChanged(newValue)
                    }
                }
#endif
        }
    }
}

struct LiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.1 : 0.45),
                                .white.opacity(0.05),
                                .clear
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.5 : 0.8),
                            .white.opacity(0.2),
                            .black.opacity(colorScheme == .dark ? 0 : 0.05)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: colorScheme == .dark ? 8 : 12, x: 0, y: 4)
    }
}

struct LiquidButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#if os(macOS)
import SwiftUI
import AppKit

struct EnterToSendTextView: NSViewRepresentable {
    @Binding var text: String
    let onTextChanged: (String) -> Void
    let onSend: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        
        // Use the TextKit 1 compatible initializer
        let textView = CenteredTextView(usingTextLayoutManager: false)
        
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 14)
        
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        // Safety check for text container
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            container.widthTracksTextView = true
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Auto-focus the text view when entering the room
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CenteredTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EnterToSendTextView
        weak var textView: NSTextView?

        init(_ parent: EnterToSendTextView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(refocusTextField),
                name: NSNotification.Name("ChatRoomFocusTextField"),
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func refocusTextField() {
            textView?.window?.makeFirstResponder(textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onTextChanged(tv.string)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSend(textView.string)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Escape: blur text field and enter keyboard navigation mode
                textView.window?.makeFirstResponder(nil)
                NotificationCenter.default.post(name: NSNotification.Name("ChatRoomEnterNavMode"), object: nil)
                return true
            }
            return false
        }
    }
}

class CenteredTextView: NSTextView {
    override var textContainerOrigin: NSPoint {
        // Safe unwrapping: if layout manager or container are missing,
        // return the default (0,0) instead of crashing.
        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer else {
            return super.textContainerOrigin
        }
        
        let rect = layoutManager.usedRect(for: textContainer)
        let containerHeight = frame.height
        let textHeight = rect.height
        
        let yOffset = (containerHeight - textHeight) / 2
        return NSPoint(x: 0, y: max(0, yOffset))
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        self.needsLayout = true
    }
}
#endif

