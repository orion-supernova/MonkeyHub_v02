import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

/// A lightweight in-app browser (WKWebView) for opening links without leaving
/// the app. Includes a title bar, progress indicator, and an "open in Safari"
/// escape hatch. iOS/macOS via WebKit; presented as a sheet.
struct InAppBrowserView: View {
    let url: URL

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var pageTitle: String = ""
    @State private var estimatedProgress: Double = 0

    private var theme: ThemeColors { selectedTheme.colors(for: colorScheme) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if estimatedProgress < 1.0 {
                    ProgressView(value: estimatedProgress)
                        .tint(theme.accent)
                        .scaleEffect(x: 1, y: 0.5, anchor: .center)
                }
                #if canImport(WebKit)
                WebViewContainer(url: url, title: $pageTitle, progress: $estimatedProgress)
                #else
                ContentUnavailableView("Browser unavailable", systemImage: "globe")
                #endif
            }
            .navigationTitle(pageTitle.isEmpty ? (url.host ?? "Web") : pageTitle)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "safari")
                    }
                }
            }
        }
    }
}

#if canImport(WebKit)
#if canImport(UIKit)
struct WebViewContainer: UIViewRepresentable {
    let url: URL
    @Binding var title: String
    @Binding var progress: Double

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        context.coordinator.observe(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        let parent: WebViewContainer
        private var observations: [NSKeyValueObservation] = []
        init(_ parent: WebViewContainer) { self.parent = parent }

        func observe(_ webView: WKWebView) {
            observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.parent.progress = wv.estimatedProgress }
            })
            observations.append(webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.parent.title = wv.title ?? "" }
            })
        }
    }
}
#else
struct WebViewContainer: NSViewRepresentable {
    let url: URL
    @Binding var title: String
    @Binding var progress: Double

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        context.coordinator.observe(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        let parent: WebViewContainer
        private var observations: [NSKeyValueObservation] = []
        init(_ parent: WebViewContainer) { self.parent = parent }

        func observe(_ webView: WKWebView) {
            observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.parent.progress = wv.estimatedProgress }
            })
            observations.append(webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.parent.title = wv.title ?? "" }
            })
        }
    }
}
#endif
#endif
