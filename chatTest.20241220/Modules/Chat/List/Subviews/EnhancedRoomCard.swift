//
//  EnhancedRoomCard.swift
//  chatTest.20241220
//
//  Created by Murat Can Koc on 3.04.2026.
//

import SwiftUI

struct EnhancedRoomCard: View {
    let room: ChatRoom
    let unreadCount: Int
    let typingText: String?
    var isSelected: Bool = false
    let action: () -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @State private var roomAvatarImage: PlatformImage?
    @State private var isLoadingAvatar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Header Row
            HStack {
                avatarView
                Spacer()
                headerButtons
            }
            .frame(height: 40)
            
            // 2. Name & Message area
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                    .lineLimit(1)
                
                Group {
                    if let typing = typingText {
                        HStack(spacing: 4) {
                            Image(systemName: "ellipsis.bubble").imageScale(.small)
                            Text(typing)
                        }
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                        
                    } else if room.type == .secret {
                        // PRIVATE ROOM LOGIC
                        if let sentAt = room.lastMessageDate,
                           let lifetime = room.messageLifetime,
                           sentAt.addingTimeInterval(lifetime) > Date() {
                            
                            let expiresAt = sentAt.addingTimeInterval(lifetime)
                            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                let remaining = max(0, expiresAt.timeIntervalSince(context.date))
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.2.circlepath")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text("Expires in \(formatCountdown(remaining))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("No recent activity")
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                        
                    } else if let lastMessage = room.lastMessage {
                        Text(lastMessage)
                            .font(.caption)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                        
                    } else {
                        Text("No messages yet")
                            .font(.caption)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.6))
                    }
                }
                .lineLimit(1)
                .frame(height: 20)
            }
            
            // 3. Footer Row
            HStack(alignment: .center, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .imageScale(.small)
                    Text("\(room.resolvedMemberCount)")
                }
                .font(.caption2)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                
                Spacer()
                
                HStack(spacing: 6) {
                    if room.type == .secret {
                        privateBadge
                    }
                    
                    if room.hasPassword {
                        passwordBadge
                    }
                }
            }
            .frame(height: 24)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(selectedTheme.colors(for: colorScheme).cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        // Tight shadow: a wide soft blur here is an offscreen GPU pass per card, recomputed every
        // frame while the sheet translates — kept small so drag/snap stays smooth.
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isSelected
                        ? selectedTheme.colors(for: colorScheme).accent
                        : .primary.opacity(0.05),
                    lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    // MARK: - Subcomponents

    private var privateBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "key.fill")
                .font(.system(size: 8))
            Text("Secret")
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.secondary.opacity(0.1)))
        .foregroundStyle(.secondary)
    }

    private var passwordBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill").font(.system(size: 8))
            Text("Locked").font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.indigo.opacity(0.1)))
        .foregroundStyle(Color.indigo)
    }

    private var avatarView: some View {
        Group {
            if let avatarImage = roomAvatarImage {
                Image(platformImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(LinearGradient(colors: selectedTheme.colors(for: colorScheme).primary, startPoint: .topLeading, endPoint: .bottomTrailing))
                    if isLoadingAvatar {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Text(room.name.prefix(1).uppercased())
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .task(id: room.avatarStorageId) {
            roomAvatarImage = nil
            guard let storageId = room.avatarStorageId else { isLoadingAvatar = false; return }
            isLoadingAvatar = true
            if let image = await ConvexFileCacheService.shared.image(for: storageId) { roomAvatarImage = image }
            isLoadingAvatar = false
        }
    }

    private var headerButtons: some View {
        HStack(spacing: 8) {
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
            Button(action: action) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).destructive)
                    .frame(width: 28, height: 28)
                    .background(selectedTheme.colors(for: colorScheme).destructive.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        else if s >= 60 { return "\(s / 60)m \(s % 60)s" }
        else { return "\(s)s" }
    }
}
