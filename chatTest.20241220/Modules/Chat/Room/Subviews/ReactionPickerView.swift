import SwiftUI

/// Modern floating reaction picker that appears above messages
struct ReactionPickerOverlay: View {
    let onEmojiSelected: (String) -> Void
    let onDismiss: () -> Void
    @State private var appeared = false
    
    private let emojis = [
        "👍", "❤️", "😂", "😮", "😢", "🙏",
        "🎉", "🔥", "✨", "💯", "👏", "🤔"
    ]
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    onEmojiSelected(emoji)
                    onDismiss()
                } label: {
                    Text(emoji)
                        .font(.system(size: 32))
                        .frame(width: 50, height: 50)
                        .scaleEffect(appeared ? 1.0 : 0.1)
                        .opacity(appeared ? 1.0 : 0.0)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        )
        .scaleEffect(appeared ? 1.0 : 0.8)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

///// Compact reaction picker with scrolling support for more emojis
//struct CompactReactionPicker: View {
//    let onEmojiSelected: (String) -> Void
//    let onDismiss: () -> Void
//    @State private var appeared = false
//    
//    private let emojis = [
//        "👍", "❤️", "😂", "😮", "😢", "🙏",
//        "🎉", "🔥", "✨", "💯", "👏", "🤔",
//        "😊", "😍", "🥳", "😎", "🤩", "💪",
//        "🙌", "👌", "✌️", "🤝", "💖", "⭐️"
//    ]
//    
//    var body: some View {
//        ScrollView(.horizontal, showsIndicators: false) {
//            HStack(spacing: 8) {
//                ForEach(Array(emojis.enumerated()), id: \.element) { index, emoji in
//                    Button {
//                        onEmojiSelected(emoji)
//                        onDismiss()
//                    } label: {
//                        Text(emoji)
//                            .font(.system(size: 32))
//                            .frame(width: 50, height: 50)
//                            .scaleEffect(appeared ? 1.0 : 0.1)
//                            .opacity(appeared ? 1.0 : 0.0)
//                            .animation(
//                                .spring(response: 0.3, dampingFraction: 0.7)
//                                    .delay(Double(index) * 0.02),
//                                value: appeared
//                            )
//                    }
//                    .buttonStyle(.plain)
//                }
//            }
//            .padding(.horizontal, 12)
//            .padding(.vertical, 8)
//        }
//        .background(
//            RoundedRectangle(cornerRadius: 30)
//                .fill(.ultraThinMaterial)
//                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
//        )
//        .frame(maxWidth: 500)
//        .scaleEffect(appeared ? 1.0 : 0.8, anchor: .top)
//        .opacity(appeared ? 1.0 : 0.0)
//        .onAppear {
//            appeared = true
//        }
//    }
//}