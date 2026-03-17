import SwiftUI
import AVKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Main Message View

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
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                )
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
            AllReactionsView(message: message, currentUserId: currentUserId) { emoji in
                Task {
                    try? await ReactionService.shared.removeReaction(
                        emoji: emoji, from: message.id, in: message.roomId
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
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(isCurrentUser ? AnyShapeStyle(bubbleColor.gradient) : AnyShapeStyle(bubbleColor))
                        )
                }
            }

            content
                // Tells iOS exactly what shape to "lift" for the context menu
                #if os(iOS)
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
                #endif
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
                            selectedEmojis: Set(message.reactions.filter { $0.userId == currentUserId }.map { $0.emoji }),
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
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    #endif
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
    
    private var bubbleColor: Color {
        isCurrentUser ? .blue : Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.15)
    }

    @ViewBuilder
    private var messageContent: some View {
        switch message.type {
        case .text:
            Text(message.content)
                .font(.system(size: 16))
                .foregroundColor(isCurrentUser ? .white : (colorScheme == .dark ? .white : .primary))
        case .image:
            ConvexImageView(
                assetURL: message.assetURL,
                storageId: message.mediaStorageId,
                imageZoomNamespace: imageZoomNamespace,
                onTap: onImageTapped
            )
        case .video:
            ConvexVideoView(
                assetURL: message.assetURL,
                storageId: message.mediaStorageId
            )
        case .audio:
            ConvexAudioView(
                assetURL: message.assetURL,
                storageId: message.mediaStorageId
            )
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
    var selectedEmojis: Set<String> = []
    let onEmojiSelected: (String) -> Void
    @State private var appeared = false
    @Environment(\.colorScheme) var colorScheme
    private static let emojis = ["❤️", "👍", "😂", "😮", "😢", "🙏", "🔥", "👏"]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(Self.emojis.enumerated()), id: \.element) { index, emoji in
                let isSelected = selectedEmojis.contains(emoji)
                Button {
                    onEmojiSelected(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .scaleEffect(appeared ? (isSelected ? 1.15 : 1.0) : 0.4)
                        .background(
                            Circle()
                                .fill(Color.blue.opacity(isSelected ? 0.25 : 0))
                                .frame(width: 38, height: 38)
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(index) * 0.02), value: appeared)
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(
            Capsule().fill(.ultraThinMaterial)
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
                .background(Color.gray.opacity(0.1))
                
                List {
                    ForEach(displayedReactions) { reaction in
                        HStack {
                            Text(reaction.emoji).font(.title3)
                            Text(reaction.userId == currentUserId ? "You" : (userNames[reaction.userId] ?? "User"))
                            Spacer()
                            if reaction.userId == currentUserId {
                                Button(action: { onRemove(reaction.emoji) }) {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Reactions")
            #if os(iOS)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            #else
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            #endif
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

// MARK: - Image Loader Manager (Cross-Platform Optimized)
final class ImageLoaderManager {
    static let shared = ImageLoaderManager()
    private let cache = NSCache<NSURL, PlatformImageWrapper>()

    func getCachedImage(for url: URL) -> PlatformImage? {
        cache.object(forKey: url as NSURL)?.image
    }

    func loadAndPrepare(url: URL) async -> PlatformImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached.image }
        return await Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 600
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

            #if canImport(UIKit)
            let image = UIImage(cgImage: cgImage)
            #elseif canImport(AppKit)
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            #endif

            self.cache.setObject(PlatformImageWrapper(image: image), forKey: url as NSURL)
            return image
        }.value
    }
}

// Wrapper class for NSCache (requires class type)
final class PlatformImageWrapper {
    let image: PlatformImage
    init(image: PlatformImage) { self.image = image }
}

struct CachedAsyncImage: View {
    let url: URL
    let imageZoomNamespace: Namespace.ID
    let onTap: (() -> Void)?
    @State private var displayImage: PlatformImage?

    var body: some View {
        ZStack {
            if let platformImage = displayImage {
                Image(platformImage: platformImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 250, height: 250)
                    .matchedTransitionSource(id: url, in: imageZoomNamespace)
            } else {
                Rectangle().fill(Color.gray.opacity(0.1)).frame(width: 250, height: 250)
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

// MARK: - Convex Media Views
// These resolve mediaStorageId → URL when no local assetURL is available (e.g. messages from other users).

private struct ConvexImageView: View {
    let assetURL: URL?
    let storageId: String?
    let imageZoomNamespace: Namespace.ID
    let onTap: (URL) -> Void

    @State private var resolvedURL: URL?

    var body: some View {
        Group {
            if let url = assetURL ?? resolvedURL {
                CachedAsyncImage(url: url, imageZoomNamespace: imageZoomNamespace, onTap: { onTap(url) })
            } else {
                ZStack {
                    Color.gray.opacity(0.15)
                    if storageId != nil {
                        ProgressView()
                    } else {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 250, height: 200)
            }
        }
        .task { await resolve() }
    }

    private func resolve() async {
        guard assetURL == nil, let storageId, resolvedURL == nil else { return }
        guard let urlString = try? await ConvexChatAPI.shared.getFileURL(storageId: storageId),
              let url = URL(string: urlString) else { return }
        resolvedURL = url
    }
}

private struct ConvexVideoView: View {
    let assetURL: URL?
    let storageId: String?

    @State private var resolvedURL: URL?

    var body: some View {
        Group {
            if let url = assetURL ?? resolvedURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: 250, height: 180)
            } else {
                ZStack {
                    Color.gray.opacity(0.15)
                    if storageId != nil {
                        ProgressView()
                    } else {
                        Image(systemName: "video").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 250, height: 180)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task { await resolve() }
    }

    private func resolve() async {
        guard assetURL == nil, let storageId, resolvedURL == nil else { return }
        guard let urlString = try? await ConvexChatAPI.shared.getFileURL(storageId: storageId),
              let url = URL(string: urlString) else { return }
        resolvedURL = url
    }
}

private struct ConvexAudioView: View {
    let assetURL: URL?
    let storageId: String?

    @State private var resolvedURL: URL?

    var body: some View {
        Group {
            if let url = assetURL ?? resolvedURL {
                AudioPlayerView(url: url).padding(8)
            } else {
                HStack(spacing: 8) {
                    if storageId != nil {
                        ProgressView()
                    } else {
                        Image(systemName: "waveform").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200, height: 44)
                .padding(8)
            }
        }
        .task { await resolve() }
    }

    private func resolve() async {
        guard assetURL == nil, let storageId, resolvedURL == nil else { return }
        guard let urlString = try? await ConvexChatAPI.shared.getFileURL(storageId: storageId),
              let url = URL(string: urlString) else { return }
        resolvedURL = url
    }
}
