import SwiftUI
import AVKit

struct MessageView: View {
    let message: ChatMessage
    let onImageTapped: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isCurrentUser: Bool {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        return message.senderId == userId
    }

    var body: some View {
        HStack {
            if isCurrentUser { Spacer() }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isCurrentUser {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                if message.type == .audio || message.type == .image {
                    messageContent
                } else {
                    messageContent
                        .padding(10)
                        .background(
                            isCurrentUser
                                ? Color.blue
                                : (colorScheme == .dark
                                    ? Color.gray.opacity(0.3) : Color.gray.opacity(0.3))
                        )
                        .cornerRadius(12)
                }
            }

            if !isCurrentUser { Spacer() }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        switch message.type {
        case .text:
            Text(message.content)
                .foregroundColor(isCurrentUser ? .white : .primary)
        case .image:
            if let url = message.assetURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(8)
                        .onTapGesture {
                            onImageTapped(url)
                        }
                } placeholder: {
                    ProgressView()
                }
                .frame(maxWidth: 200, maxHeight: 200)
            }
        case .video:
            if let url = message.assetURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: 200, height: 200)
                    .cornerRadius(8)
            }
        case .url:
            if let url = URL(string: message.content) {
                Link(message.content, destination: url)
                    .foregroundColor(isCurrentUser ? .white : .blue)
            }
        case .audio:
            if let url = message.assetURL {
                AudioPlayerView(url: url)
            }
        }
    }
}
