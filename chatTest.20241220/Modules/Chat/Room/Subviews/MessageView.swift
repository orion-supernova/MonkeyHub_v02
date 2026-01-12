import SwiftUI
import AVKit

struct MessageView: View {
    let message: ChatMessage
    let onImageTapped: (URL) -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic

    private var isCurrentUser: Bool {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        return message.senderId == userId
    }
    
    private var isSystemMessage: Bool {
        return message.senderId == ChatMessage.systemSenderId
    }

    var body: some View {
        if isSystemMessage {
            systemMessageView
        } else {
            regularMessageView
        }
    }
    
    private var systemMessageView: some View {
        HStack {
            Spacer()
            
            Text(message.content)
                .font(.caption)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selectedTheme.colors(for: colorScheme).cardBackground.opacity(0.6))
                )
                .padding(.vertical, 4)
            
            Spacer()
        }
    }
    
    private var regularMessageView: some View {
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
            .contextMenu {
                if isCurrentUser {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            if !isCurrentUser { Spacer() }
            
            // Status Indicator (Only for current user)
            if isCurrentUser && message.status != .sent {
                switch message.status {
                case .pending:
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                        .padding(.trailing, 4)
                case .error:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.trailing, 4)
                default:
                    EmptyView()
                }
            }
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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        // Loading state
                        ZStack {
                            Color.gray.opacity(0.1)
                            ProgressView()
                        }
                        .frame(width: 200, height: 200)
                        .cornerRadius(8)
                    case .success(let image):
                        // Image loaded - fill entire frame to avoid empty space
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .cornerRadius(8)
                            .clipped()
                            .onTapGesture {
                                onImageTapped(url)
                            }
                    case .failure:
                        // Error state
                        ZStack {
                            Color.gray.opacity(0.1)
                            Image(systemName: "photo.fill")
                                .foregroundColor(.gray)
                        }
                        .frame(width: 200, height: 200)
                        .cornerRadius(8)
                    @unknown default:
                        EmptyView()
                    }
                }
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
        case .system:
            EmptyView()
        }
    }
}