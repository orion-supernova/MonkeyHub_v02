import SwiftUI
import AVKit

struct MessageView: View {
    let message: ChatMessage
    let onImageTapped: (URL) -> Void
    let onDelete: () -> Void
    @Binding var showReactionPicker: Bool
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @State private var showAllReactions = false

    private var isCurrentUser: Bool {
        let userId = userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
        return message.senderId == userId
    }
    
    private var currentUserId: String {
        userDefaults.string(forKey: userIdUserDefaultsKey) ?? ""
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
        VStack(spacing: 0) {
            if showReactionPicker {
                CompactReactionPicker(
                    onEmojiSelected: { emoji in
                        Task {
                            try? await ReactionService.shared.toggleReaction(
                                emoji: emoji,
                                on: message.id,
                                in: message.roomId
                            )
                        }
                        showReactionPicker = false
                    },
                    onDismiss: {
                        showReactionPicker = false
                    }
                )
                .padding(.bottom, 8)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            
            HStack(alignment: .bottom, spacing: 0) {
                if isCurrentUser { Spacer(minLength: 60) }

                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 2) {
                    if !isCurrentUser {
                        Text(message.senderName)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.leading, 12)
                            .padding(.bottom, 2)
                    }

                    // Message bubble
                    Group {
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
                    .onTapGesture(count: 2) {
                        showReactionPicker.toggle()
                    }
                    .contextMenu {
                        Button {
                            showReactionPicker = true
                        } label: {
                            Label("React", systemImage: "face.smiling")
                        }
                        
                        if isCurrentUser {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    
                    // Reactions below message - closer spacing
                    if !message.reactions.isEmpty {
                        ReactionsBarView(
                            message: message,
                            currentUserId: currentUserId,
                            isCurrentUserMessage: isCurrentUser,
                            onShowAllReactions: {
                                showAllReactions = true
                            }
                        )
                        .padding(.top, 2)
                    }
                }

                if !isCurrentUser { Spacer(minLength: 60) }
                
                if isCurrentUser && message.status != .sent {
                    switch message.status {
                    case .pending:
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                            .padding(.leading, 4)
                    case .error:
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.leading, 4)
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .sheet(isPresented: $showAllReactions) {
            AllReactionsView(message: message, currentUserId: currentUserId) { reactionId in
                Task {
                    try? await ReactionService.shared.removeReaction(
                        reactionId: reactionId,
                        from: message.id,
                        in: message.roomId
                    )
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
                        ZStack {
                            Color.gray.opacity(0.1)
                            ProgressView()
                        }
                        .frame(width: 200, height: 200)
                        .cornerRadius(8)
                    case .success(let image):
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

struct AllReactionsView: View {
    let message: ChatMessage
    let currentUserId: String
    let onRemove: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var userNames: [String: String] = [:]
    @State private var selectedTab = 0
    
    private var groupedReactions: [ReactionGroup] {
        message.groupedReactions()
    }
    
    private var allReactions: [MessageReaction] {
        message.reactions.sorted { $0.timestamp < $1.timestamp }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Emoji tabs
                if groupedReactions.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            // All tab
                            TabButton(
                                title: "All",
                                count: allReactions.count,
                                isSelected: selectedTab == 0
                            ) {
                                selectedTab = 0
                            }
                            
                            // Individual emoji tabs
                            ForEach(Array(groupedReactions.enumerated()), id: \.element.id) { index, group in
                                TabButton(
                                    emoji: group.emoji,
                                    count: group.count,
                                    isSelected: selectedTab == index + 1
                                ) {
                                    selectedTab = index + 1
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .background(Color.secondary.opacity(0.05))
                }
                
                // Reactions list
                List {
                    ForEach(displayedReactions) { reaction in
                        HStack(spacing: 12) {
                            Text(reaction.emoji)
                                .font(.title2)
                            
                            if reaction.userId == currentUserId {
                                Text("You")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.blue)
                            } else {
                                Text(userNames[reaction.userId] ?? "Loading...")
                                    .font(.body)
                            }
                            
                            Spacer()
                            
                            if reaction.userId == currentUserId {
                                Button {
                                    onRemove(reaction.id)
                                    if allReactions.count == 1 {
                                        dismiss()
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.title3)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Reactions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadUserNames()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private var displayedReactions: [MessageReaction] {
        if selectedTab == 0 {
            return allReactions
        } else if selectedTab - 1 < groupedReactions.count {
            return groupedReactions[selectedTab - 1].reactions
        }
        return []
    }
    
    private func loadUserNames() async {
        let otherUserIds = message.reactions
            .filter { $0.userId != currentUserId }
            .map { $0.userId }
        
        if !otherUserIds.isEmpty {
            userNames = await UserCacheService.shared.getUserNames(for: otherUserIds)
        }
    }
}

struct TabButton: View {
    var emoji: String?
    var title: String?
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let emoji = emoji {
                    Text(emoji)
                        .font(.title3)
                } else if let title = title {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                }
                
                Text("\(count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.blue : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}