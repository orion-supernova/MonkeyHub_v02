import SwiftUI
import AVKit

// MARK: - Main Message View
import SwiftUI
import AVKit

struct MessageView: View {
    let message: ChatMessage
    let currentUserId: String
    let isCurrentUser: Bool
    let onImageTapped: (URL) -> Void
    let onDelete: () -> Void
    let onRequestReactionPicker: () -> Void
    let isReactionPickerActive: Bool

    let imageZoomNamespace: Namespace.ID
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAllReactions = false

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
            HStack(alignment: .bottom, spacing: 0) {
                if isCurrentUser { Spacer(minLength: 60) }

                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                    if !isCurrentUser {
                        Text(message.senderName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)
                    }

                    ZStack(alignment: isCurrentUser ? .bottomTrailing : .bottomLeading) {
                        messageContentWrapper

                        // Reaction Badge (The small one on the bubble)
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
            .padding(.bottom, message.reactions.isEmpty ? 6 : 22)
        }
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
            let content = Group {
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

            content
                // Tells iOS exactly what shape to "lift" for the context menu
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contextMenu {
                    Button(action: {
                        // Small delay to let menu close before picker pops
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onRequestReactionPicker()
                        }
                    }) {
                        Label("React", systemImage: "face.smiling")
                    }

                    if isCurrentUser {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                // THE PICKER OVERLAY
                .overlay(alignment: isCurrentUser ? .topTrailing : .topLeading) {
                    if isReactionPickerActive {
                        CompactReactionPicker(
                            onEmojiSelected: { emoji in
                                toggleReaction(emoji)
                                onRequestReactionPicker()
                            }
                        )
                        .offset(y: -55)
                        // High Z-index here to ensure it's above the badge
                        .zIndex(1000)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.1, anchor: isCurrentUser ? .bottomTrailing : .bottomLeading).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.8))
                        ))
                    }
                }
                .onTapGesture(count: 2) {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onRequestReactionPicker()
                }
                .onTapGesture {
                    // Only handle reaction picker dismissal here
                    // Image taps are handled directly on the image view
                    if isReactionPickerActive {
                        onRequestReactionPicker()
                    }
                }
        }
    
    private var bubbleBackground: some View {
        Group {
            if isCurrentUser {
                Rectangle().fill(Color.blue.gradient)
            } else {
                Rectangle().fill(Color(.systemGray5).opacity(colorScheme == .dark ? 0.8 : 1.0))
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        switch message.type {
        case .text:
            Text(message.content)
                .font(.system(size: 16))
                .foregroundColor(isCurrentUser ? .white : (colorScheme == .dark ? .white : .primary))
        case .image:
            if let url = message.assetURL {
                CachedAsyncImage(
                    url: url,
                    imageZoomNamespace: imageZoomNamespace,
                    onTap: { onImageTapped(url) }
                )
            }
        case .video:
            if let url = message.assetURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: 250, height: 250)
            }
        case .audio:
            if let url = message.assetURL {
                AudioPlayerView(url: url).padding(8)
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

// MARK: - FIXED Compact Reaction Picker
struct CompactReactionPicker: View {
    let onEmojiSelected: (String) -> Void
    @State private var appeared = false
    @Environment(\.colorScheme) var colorScheme
    private static let emojis = ["❤️", "👍", "😂", "😮", "😢", "🙏", "🔥", "👏"]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(Self.emojis.enumerated()), id: \.element) { index, emoji in
                Button {
                    onEmojiSelected(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .scaleEffect(appeared ? 1.0 : 0.4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(index) * 0.02), value: appeared)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        // ADDED: A solid background behind the material so it doesn't look dark when dimmed
        .background(
            ZStack {
//                Capsule().fill(colorScheme == .dark ? Color(white: 0.2) : Color.white)
                Capsule().fill(.ultraThinMaterial)
            }
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 15, y: 10)
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        .fixedSize()
        .onAppear { appeared = true }
    }
}

// MARK: - Integrated Badge
struct IntegratedReactionBadge: View {
    let message: ChatMessage
    let currentUserId: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                ForEach(message.groupedReactions().prefix(3)) { group in
                    Text(group.emoji).font(.system(size: 12))
                }
                if message.reactions.count > 1 {
                    Text("\(message.reactions.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - All Reactions Detail (Sheet)
struct AllReactionsView: View {
    let message: ChatMessage
    let currentUserId: String
    let onRemove: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var userNames: [String: String] = [:]
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
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
                            Spacer()
                            if reaction.userId == currentUserId {
                                Button(action: { onRemove(reaction.id) }) {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Reactions")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task {
                userNames = await UserCacheService.shared.getUserNames(for: message.reactions.map { $0.userId })
            }
        }
    }
    
    private var displayedReactions: [MessageReaction] {
        if selectedTab == 0 { return message.reactions }
        let groups = message.groupedReactions()
        return groups.indices.contains(selectedTab - 1) ? groups[selectedTab - 1].reactions : []
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

// MARK: - Image Loader Manager (UIKit/IO Optimized)
final class ImageLoaderManager {
    static let shared = ImageLoaderManager()
    private let cache = NSCache<NSURL, UIImage>()
    func getCachedImage(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func loadAndPrepare(url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        return await Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 600
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let uiImage = UIImage(cgImage: cgImage)
            self.cache.setObject(uiImage, forKey: url as NSURL)
            return uiImage
        }.value
    }
}

struct CachedAsyncImage: View {
    let url: URL
    let imageZoomNamespace: Namespace.ID
    let onTap: (() -> Void)?
    @State private var displayImage: UIImage?

    var body: some View {
        ZStack {
            if let uiImage = displayImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 250, height: 250)
                    .matchedTransitionSource(id: url, in: imageZoomNamespace)
            } else {
                Rectangle().fill(Color(.systemGray6)).frame(width: 250, height: 250)
                    .overlay { ProgressView() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .task {
            if displayImage == nil {
                displayImage = await ImageLoaderManager.shared.loadAndPrepare(url: url)
            }
        }
    }
}
