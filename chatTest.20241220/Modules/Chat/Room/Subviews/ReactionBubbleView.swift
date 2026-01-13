import SwiftUI

struct ReactionBubbleView: View {
    let reactionGroup: ReactionGroup
    let isCurrentUserReaction: Bool
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(reactionGroup.emoji)
                    .font(.system(size: 15))
                
                Text("\(reactionGroup.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isCurrentUserReaction ? Color.blue : Color.primary.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var backgroundColor: Color {
        if isCurrentUserReaction {
            return colorScheme == .dark 
                ? Color.blue.opacity(0.2) 
                : Color.blue.opacity(0.1)
        } else {
            return colorScheme == .dark 
                ? Color.white.opacity(0.05) 
                : Color.black.opacity(0.03)
        }
    }
    
    private var borderColor: Color {
        if isCurrentUserReaction {
            return colorScheme == .dark 
                ? Color.blue.opacity(0.5) 
                : Color.blue.opacity(0.4)
        } else {
            return colorScheme == .dark 
                ? Color.white.opacity(0.15) 
                : Color.black.opacity(0.15)
        }
    }
}

struct ReactionsBarView: View {
    let message: ChatMessage
    let currentUserId: String
    let isCurrentUserMessage: Bool
    let onShowAllReactions: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var groupedReactions: [ReactionGroup] {
        message.groupedReactions()
    }
    
    private let maxVisibleReactions = 3
    
    var body: some View {
        if !groupedReactions.isEmpty {
            HStack(spacing: 4) {
                ForEach(groupedReactions.prefix(maxVisibleReactions)) { group in
                    ReactionBubbleView(
                        reactionGroup: group,
                        isCurrentUserReaction: group.containsUser(currentUserId),
                        onTap: onShowAllReactions
                    )
                }
                
                if groupedReactions.count > maxVisibleReactions {
                    Button(action: onShowAllReactions) {
                        Text("+\(groupedReactions.count - maxVisibleReactions)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(colorScheme == .dark 
                                        ? Color.white.opacity(0.05) 
                                        : Color.black.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        colorScheme == .dark 
                                            ? Color.white.opacity(0.15) 
                                            : Color.black.opacity(0.15),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, isCurrentUserMessage ? 0 : 12)
            .padding(.trailing, isCurrentUserMessage ? 12 : 0)
        }
    }
}

/// Simple flow layout that wraps items to next line
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}