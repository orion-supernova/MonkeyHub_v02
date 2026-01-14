import SwiftUI
import AVKit

// MARK: - Main Message View
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
    
    var body: some View {
        if message.senderId == ChatMessage.systemSenderId {
            systemMessageView
        } else {
            regularMessageView
        }
    }
    
    private var systemMessageView: some View {
        HStack {
            Spacer()
            Text(message.content)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                .padding(.vertical, 8)
            Spacer()
        }
    }
    
    private var regularMessageView: some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 0) {
            
            // 1. REACTION PICKER
            if showReactionPicker {
                CompactReactionPicker(
                    onEmojiSelected: { emoji in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        toggleReaction(emoji)
                        withAnimation(.spring(response: 0.3)) { showReactionPicker = false }
                    },
                    onDismiss: {
                        withAnimation { showReactionPicker = false }
                    }
                )
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.1, anchor: isCurrentUser ? .bottomTrailing : .bottomLeading).combined(with: .opacity),
                    removal: .opacity
                ))
                .zIndex(100)
            }
            
            HStack(alignment: .bottom, spacing: 0) {
                if isCurrentUser { Spacer(minLength: 60) }

                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                    if !isCurrentUser {
                        Text(message.senderName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)
                            .padding(.bottom, -2)
                    }

                    // 2. MESSAGE BUBBLE
                    ZStack(alignment: isCurrentUser ? .bottomTrailing : .bottomLeading) {
                        messageContentWrapper
                        
                        // Integrated Badge
                        if !message.reactions.isEmpty {
                            IntegratedReactionBadge(
                                message: message,
                                currentUserId: currentUserId,
                                onTap: { showAllReactions = true }
                            )
                            .offset(x: isCurrentUser ? -12 : 12, y: 14)
                            .zIndex(110)
                        }
                    }
                }

                if !isCurrentUser { Spacer(minLength: 60) }
            }
            .padding(.bottom, message.reactions.isEmpty ? 6 : 20)
        }
        .zIndex(showReactionPicker ? 1000 : 1)
        .sheet(isPresented: $showAllReactions) {
            AllReactionsView(message: message, currentUserId: currentUserId) { reactionId in
                Task {
                    try? await ReactionService.shared.removeReaction(
                        reactionId: reactionId, from: message.id, in: message.roomId
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var messageContentWrapper: some View {
        Group {
            if message.type == .audio || message.type == .image || message.type == .video {
                messageContent
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                messageContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .cornerRadius(20)
            }
        }
        .scaleEffect(showReactionPicker ? 1.06 : 1.0)
        .shadow(color: .black.opacity(showReactionPicker ? 0.25 : 0), radius: 15, y: 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: showReactionPicker)
        .onTapGesture(count: 2) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showReactionPicker.toggle()
            }
        }
        .contextMenu {
            Button { withAnimation { showReactionPicker = true } } label: {
                Label("React", systemImage: "face.smiling")
            }
            if isCurrentUser {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    // FIXED GRADIENT LOGIC
    private var bubbleBackground: some View {
        Group {
            if isCurrentUser {
                Rectangle()
                    .fill(Color.blue.gradient)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5).opacity(colorScheme == .dark ? 0.8 : 1.0))
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        switch message.type {
        case .text:
            Text(message.content)
                .font(.system(size: 16))
                .foregroundColor(isCurrentUser ? .white : .primary)
        case .image:
            if let url = message.assetURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                            .frame(width: 250, height: 250).clipped()
                            .onTapGesture { onImageTapped(url) }
                    } else {
                        Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 250, height: 250)
                    }
                }
            }
        case .video:
            if let url = message.assetURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: 250, height: 250)
            }
        case .audio:
            if let url = message.assetURL {
                AudioPlayerView(url: url)
                    .padding(8)
            }
        default: EmptyView()
        }
    }

    private func toggleReaction(_ emoji: String) {
        Task {
            try? await ReactionService.shared.toggleReaction(
                emoji: emoji, on: message.id, in: message.roomId
            )
        }
    }
}

// MARK: - Modern Integrated Reaction Badge
struct IntegratedReactionBadge: View {
    let message: ChatMessage
    let currentUserId: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                ForEach(message.groupedReactions().prefix(3)) { group in
                    Text(group.emoji).font(.system(size: 13))
                }
                if message.reactions.count > 1 {
                    Text("\(message.reactions.count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modern Compact Reaction Picker
struct CompactReactionPicker: View {
    let onEmojiSelected: (String) -> Void
    let onDismiss: () -> Void
    @State private var appeared = false
    
    private let emojis = ["❤️", "👍", "😂", "😮", "😢", "🙏", "🔥", "👏"]
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(emojis.enumerated()), id: \.element) { index, emoji in
                Button {
                    onEmojiSelected(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 28))
                        .scaleEffect(appeared ? 1.0 : 0.4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(index) * 0.04), value: appeared)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
        .onAppear { appeared = true }
    }
}

// MARK: - All Reactions Detail View (Sheet)
struct AllReactionsView: View {
    let message: ChatMessage
    let currentUserId: String
    let onRemove: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var userNames: [String: String] = [:]
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        TabButton(title: "All", count: message.reactions.count, isSelected: selectedTab == 0) { selectedTab = 0 }
                        ForEach(Array(message.groupedReactions().enumerated()), id: \.element.id) { index, group in
                            TabButton(emoji: group.emoji, count: group.count, isSelected: selectedTab == index + 1) { selectedTab = index + 1 }
                        }
                    }
                    .padding()
                }
                .background(Color(.secondarySystemBackground))
                
                List {
                    ForEach(displayedReactions) { reaction in
                        HStack {
                            Text(reaction.emoji).font(.title3)
                            Text(reaction.userId == currentUserId ? "You" : (userNames[reaction.userId] ?? "User"))
                                .font(.body)
                            Spacer()
                            if reaction.userId == currentUserId {
                                Button(action: {
                                    onRemove(reaction.id)
                                    if message.reactions.count <= 1 { dismiss() }
                                }) {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task {
                let ids = message.reactions.map { $0.userId }
                userNames = await UserCacheService.shared.getUserNames(for: ids)
            }
        }
    }
    
    private var displayedReactions: [MessageReaction] {
        if selectedTab == 0 { return message.reactions }
        let groups = message.groupedReactions()
        guard selectedTab - 1 < groups.count else { return [] }
        return groups[selectedTab - 1].reactions
    }
}

struct TabButton: View {
    var emoji: String? = nil
    var title: String? = nil
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let e = emoji { Text(e) } else { Text(title ?? "") }
                Text("\(count)").font(.caption).bold().opacity(0.6)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.blue : Color.primary.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
