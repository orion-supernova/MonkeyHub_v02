import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

struct ExportsBrowserView: View {
    @State private var exports: [ExportBundle] = []
    @State private var showingShareSheet: Bool = false
    @State private var shareURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if exports.isEmpty {
                    ContentUnavailableView("No Exports", systemImage: "tray", description: Text("Run an export to see bundles here."))
                } else {
                    ForEach(exports) { bundle in
                        NavigationLink(value: bundle) {
                            HStack(spacing: 12) {
                                Image(systemName: "externaldrive.badge.icloud")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bundle.displayName)
                                        .font(.headline)
                                    Text(bundle.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteBundle(bundle)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                openFolder(bundle)
                            } label: {
                                Label("Open", systemImage: "folder")
                            }
                            Button {
                                shareFolder(bundle)
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Exports")
            .toolbar {
                ToolbarItem(placement: {
                    #if canImport(UIKit)
                    return .navigationBarLeading
                    #else
                    return .cancellationAction
                    #endif
                }()) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: {
                    #if canImport(UIKit)
                    return .navigationBarTrailing
                    #else
                    return .automatic
                    #endif
                }()) {
                    Button {
                        refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(for: ExportBundle.self) { bundle in
                ExportDetailView(bundle: bundle)
            }
            .onAppear { refresh() }
            #if canImport(UIKit)
            .sheet(isPresented: $showingShareSheet) {
                if let shareURL = shareURL {
                    ActivityView(activityItems: [shareURL])
                }
            }
            #endif
        }
    }

    private func refresh() {
        exports = ExportBundle.scan()
    }

    private func deleteBundle(_ bundle: ExportBundle) {
        do {
            if let json = bundle.jsonURL { try FileManager.default.removeItem(at: json) }
            if let folder = bundle.folderURL { try? FileManager.default.removeItem(at: folder) }
            refresh()
        } catch {
            print("❌ Failed to delete bundle: \(error)")
        }
    }

    private func openFolder(_ bundle: ExportBundle) {
        guard let folder = bundle.folderURL else { return }
        #if os(iOS)
        UIApplication.shared.open(folder)
        #elseif os(macOS)
        NSWorkspace.shared.open(folder)
        #endif
    }

    private func shareFolder(_ bundle: ExportBundle) {
        guard let folder = bundle.folderURL else { return }
        shareURL = folder
        showingShareSheet = true
    }
}

// MARK: - Detail View
struct ExportDetailView: View {
    let bundle: ExportBundle
    @State private var assets: [URL] = []

    var body: some View {
        List {
            Section("Info") {
                LabeledContent("JSON") { Text(bundle.jsonURL?.lastPathComponent ?? "—") }
                LabeledContent("Folder") { Text(bundle.folderURL?.lastPathComponent ?? "—") }
                LabeledContent("Bundle Size") { Text(bundle.bundleSizeString) }
                LabeledContent("Assets") { Text("\(assets.count)") }
            }
            if !assets.isEmpty {
                Section("Asset Files") {
                    ForEach(assets, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                Text(fileSizeString(url))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(bundle.displayName)
        .onAppear { loadAssets() }
    }

    private func loadAssets() {
        guard let folder = bundle.folderURL else { return }
        let assetsDir = folder.appendingPathComponent("Assets", isDirectory: true)
        guard FileManager.default.fileExists(atPath: assetsDir.path) else { return }
        if let files = try? FileManager.default.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            assets = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    private func fileSizeString(_ url: URL) -> String {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            let fmt = ByteCountFormatter(); fmt.countStyle = .file
            return fmt.string(fromByteCount: Int64(size))
        }
        return "—"
    }
}

// MARK: - Model
struct ExportBundle: Identifiable, Hashable {
    let id = UUID()
    let baseName: String
    let jsonURL: URL?
    let folderURL: URL?
    let bundleSize: Int64

    var displayName: String { baseName }

    var summary: String {
        let fmt = ByteCountFormatter(); fmt.countStyle = .file
        let count = filesCount()
        return "Files: \(count), Size: \(bundleSizeString)"
    }

    var bundleSizeString: String {
        let fmt = ByteCountFormatter(); fmt.countStyle = .file
        return fmt.string(fromByteCount: bundleSize)
    }

    private func filesCount() -> Int {
        guard let folder = folderURL else { return 0 }
        let fm = FileManager.default
        var count = 0
        if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for _ in enumerator {
                count += 1
            }
        }
        return count
    }

    static func scan() -> [ExportBundle] {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // Find root JSON files
        let jsons = (try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?.filter { $0.lastPathComponent.hasPrefix("migration_export_") && $0.pathExtension == "json" } ?? []

        var results: [ExportBundle] = []
        for json in jsons {
            let base = json.deletingPathExtension().lastPathComponent
            let folder = docs.appendingPathComponent(base, isDirectory: true)
            var total: Int64 = 0
            let fm = FileManager.default
            if fm.fileExists(atPath: folder.path) {
                if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        if let isRegular = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isRegular == true,
                           let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            total += Int64(size)
                        }
                    }
                }
            }
            results.append(ExportBundle(baseName: base, jsonURL: json, folderURL: fm.fileExists(atPath: folder.path) ? folder : nil, bundleSize: total))
        }

        return results.sorted { $0.baseName > $1.baseName }
    }
}

#if canImport(UIKit)
// MARK: - ActivityView for sharing (iOS only)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif