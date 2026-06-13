import Foundation

/// Open Graph metadata for a URL, used to render rich link preview cards.
struct LinkPreview: Equatable {
    let url: URL
    let title: String?
    let description: String?
    let imageURL: URL?
    let siteName: String?

    /// True when there's nothing richer than the bare URL to show.
    var isEmpty: Bool { title == nil && description == nil && imageURL == nil }
}

/// Fetches and caches Open Graph metadata for links. Pure URLSession + a tiny
/// regex HTML scrape — no third-party HTML parser dependency.
actor LinkPreviewService {
    static let shared = LinkPreviewService()

    private var cache: [String: LinkPreview] = [:]
    private var inFlight: [String: Task<LinkPreview?, Never>] = [:]

    /// Returns the first URL contained in `text`, if any.
    nonisolated static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let match = detector.firstMatch(in: text, options: [], range: range)
        guard let url = match?.url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    func preview(for url: URL) async -> LinkPreview? {
        let key = url.absoluteString
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<LinkPreview?, Never> { [url] in
            await Self.fetchPreview(url: url)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { cache[key] = result }
        return result
    }

    private static func fetchPreview(url: URL) async -> LinkPreview? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (compatible; MonkeyHub/1.0)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let contentType = http.value(forHTTPHeaderField: "Content-Type"),
              contentType.lowercased().contains("text/html")
        else { return nil }

        // Only need the <head>; cap parsing to the first 200KB for speed.
        let slice = data.prefix(200_000)
        guard let html = String(data: slice, encoding: .utf8)
            ?? String(data: slice, encoding: .isoLatin1) else { return nil }

        let title = metaContent(in: html, property: "og:title") ?? titleTag(in: html)
        let description = metaContent(in: html, property: "og:description")
            ?? metaName(in: html, name: "description")
        let image = metaContent(in: html, property: "og:image")
        let site = metaContent(in: html, property: "og:site_name") ?? url.host

        let preview = LinkPreview(
            url: url,
            title: title?.htmlDecoded,
            description: description?.htmlDecoded,
            imageURL: image.flatMap { URL(string: $0, relativeTo: url)?.absoluteURL },
            siteName: site?.htmlDecoded
        )
        return preview.isEmpty ? nil : preview
    }

    // MARK: - Tiny HTML scrapers

    private static func metaContent(in html: String, property: String) -> String? {
        // Matches <meta property="og:x" content="..."> in either attribute order.
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"'][^>]+content=[\"']([^\"']*)[\"']",
            "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+(?:property|name)=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"']"
        ]
        for p in patterns {
            if let v = firstCapture(in: html, pattern: p), !v.isEmpty { return v }
        }
        return nil
    }

    private static func metaName(in html: String, name: String) -> String? {
        metaContent(in: html, property: name)
    }

    private static func titleTag(in html: String) -> String? {
        firstCapture(in: html, pattern: "<title[^>]*>([^<]*)</title>")
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    /// Minimal HTML entity decode for the handful of entities common in OG tags.
    var htmlDecoded: String {
        var s = self
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        for (k, v) in map { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }
}
