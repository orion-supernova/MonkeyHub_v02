import SwiftUI

/// A text message body that renders the content and, if it contains a link,
/// an Open Graph preview card beneath it.
struct LinkifiedTextMessage: View {
    let content: String
    let isCurrentUser: Bool
    @AppStorage(AppearanceKeys.showLinkUrls) private var showLinkUrls = false
    @Environment(\.colorScheme) private var colorScheme

    private var detectedURL: URL? { LinkPreviewService.firstURL(in: content) }

    /// Hide the raw text only when the message *is* just the URL and the user
    /// hasn't opted to keep URL text visible — the preview card stands alone.
    private var hideText: Bool {
        guard !showLinkUrls, let url = detectedURL else { return false }
        return content.trimmingCharacters(in: .whitespacesAndNewlines) == url.absoluteString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hideText {
                Text(content)
                    .font(.system(size: 16))
                    .foregroundColor(isCurrentUser ? .white : (colorScheme == .dark ? .white : .primary))
                    .textSelection(.enabled)
            }

            if let url = detectedURL {
                LinkPreviewCard(url: url, isCurrentUser: isCurrentUser)
            }
        }
    }
}

/// Rich preview card for a single URL. Loads metadata lazily and is tappable.
struct LinkPreviewCard: View {
    let url: URL
    let isCurrentUser: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var preview: LinkPreview?
    @State private var didLoad = false
    @State private var showInAppBrowser = false

    private func openLink() {
        #if canImport(UIKit)
        showInAppBrowser = true
        #else
        openURL(url)
        #endif
    }

    private var surface: Color {
        isCurrentUser ? Color.white.opacity(0.18)
                      : Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06)
    }

    var body: some View {
        Group {
            if let preview {
                content(for: preview)
            } else if !didLoad {
                // Slim placeholder while metadata loads.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(url.host ?? url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(isCurrentUser ? .white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: 240, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(surface))
            }
        }
        .task {
            preview = await LinkPreviewService.shared.preview(for: url)
            didLoad = true
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showInAppBrowser) {
            InAppBrowserView(url: url)
        }
        #endif
    }

    @ViewBuilder
    private func content(for preview: LinkPreview) -> some View {
        Button {
            openLink()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let imageURL = preview.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Rectangle().fill(surface)
                        }
                    }
                    .frame(width: 240, height: 130)
                    .clipped()
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let site = preview.siteName {
                        Text(site.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isCurrentUser ? .white.opacity(0.8) : .secondary)
                            .lineLimit(1)
                    }
                    if let title = preview.title {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isCurrentUser ? .white : .primary)
                            .lineLimit(2)
                    }
                    if let desc = preview.description {
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundStyle(isCurrentUser ? .white.opacity(0.85) : .secondary)
                            .lineLimit(2)
                    }
                }
                .padding(10)
            }
            .frame(width: 240, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(surface))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
