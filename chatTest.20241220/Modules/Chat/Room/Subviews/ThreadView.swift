import SwiftUI

/// A focused "cinematic" view of a reply chain — loads the full thread around a
/// root message via `messages:getThread` and presents it as a clean timeline.
struct ThreadView: View {
    let rootMessageId: String
    let currentUserId: String

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var isLoading = true

    private var theme: ThemeColors { selectedTheme.colors(for: colorScheme) }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: theme.sheetGradient + [theme.background],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(theme.accent)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                ThreadBubble(
                                    message: message,
                                    isCurrentUser: message.senderId == currentUserId,
                                    isConnectedToPrevious: index > 0,
                                    theme: theme
                                )
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Thread")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        defer { isLoading = false }
        messages = (try? await ConvexChatAPI.shared.fetchThread(messageId: rootMessageId)) ?? []
    }
}

private struct ThreadBubble: View {
    let message: ChatMessage
    let isCurrentUser: Bool
    let isConnectedToPrevious: Bool
    let theme: ThemeColors

    private var bodyText: String {
        switch message.type {
        case .image: return "📷 Photo"
        case .video: return "🎬 Video"
        case .audio: return "🎙 Voice message"
        default: return message.content
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isConnectedToPrevious {
                // Connecting tether line for the cinematic chain feel.
                Rectangle()
                    .fill(theme.accent.opacity(0.3))
                    .frame(width: 2, height: 12)
                    .padding(.leading, 18)
            }
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(LinearGradient(colors: theme.primary, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(message.senderName.prefix(1).uppercased())
                            .font(.subheadline.bold())
                            .foregroundStyle(theme.text)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(message.senderName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isCurrentUser ? theme.accent : theme.textPrimary)
                        Spacer()
                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Text(bodyText)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isCurrentUser ? theme.accent.opacity(0.3) : theme.textSecondary.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
