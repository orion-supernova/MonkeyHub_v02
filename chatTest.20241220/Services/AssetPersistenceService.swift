import CryptoKit
import Foundation

/// Handles local file-based persistence for media assets sent in chat.
class AssetPersistenceService {
    static let shared = AssetPersistenceService()
    private let fileManager = FileManager.default
    
    // The directory changes every time the app launches
    private var assetsDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let assetsDir = paths[0].appendingPathComponent("ChatAssets", isDirectory: true)
        if !fileManager.fileExists(atPath: assetsDir.path) {
            try? fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        }
        return assetsDir
    }

    /// Resolves a simple filename into a valid URL for the current app session
    func getURL(for filename: String?) -> URL? {
        guard let filename = filename, !filename.isEmpty else { return nil }
        // Always looks inside the current session's ChatAssets directory
        return assetsDirectory.appendingPathComponent(filename)
    }

    /// Copy a local file into the persistent ChatAssets directory.
    func persistAsset(from sourceURL: URL) -> URL? {
        let fileName = sourceURL.lastPathComponent
        let destinationURL = assetsDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            return sourceURL
        }
    }
}

final class CachedPlatformImage {
    let image: PlatformImage

    init(image: PlatformImage) {
        self.image = image
    }
}

@MainActor
final class ConvexFileCacheService {
    static let shared = ConvexFileCacheService()

    private struct URLCacheEntry {
        let url: URL
        let expiresAt: Date
    }

    private let fileManager = FileManager.default
    private let imageCache = NSCache<NSString, CachedPlatformImage>()
    private let manifestURL: URL
    private let cacheDirectory: URL
    private let signedURLTTL: TimeInterval = 60 * 20

    private var manifest: [String: String]
    private var signedURLCache: [String: URLCacheEntry] = [:]
    private var urlTasks: [String: Task<URL?, Never>] = [:]
    private var downloadTasks: [String: Task<URL?, Never>] = [:]

    private init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsDirectory
            .appendingPathComponent("ChatAssets", isDirectory: true)
            .appendingPathComponent("ConvexCache", isDirectory: true)
        manifestURL = cacheDirectory.appendingPathComponent("manifest.json")

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            manifest = decoded
        } else {
            manifest = [:]
        }

        imageCache.countLimit = 160
    }

    func cachedLocalFileURL(for storageId: String?) -> URL? {
        guard let storageId,
              let fileName = manifest[storageId] else { return nil }

        let url = cacheDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            manifest.removeValue(forKey: storageId)
            persistManifest()
            return nil
        }
        return url
    }

    func image(for storageId: String?) async -> PlatformImage? {
        guard let storageId else { return nil }

        if let image = imageCache.object(forKey: storageId as NSString)?.image {
            return image
        }

        if let localURL = cachedLocalFileURL(for: storageId),
           let image = await Self.loadImage(from: localURL) {
            imageCache.setObject(CachedPlatformImage(image: image), forKey: storageId as NSString)
            return image
        }

        guard let localURL = await downloadFile(storageId: storageId),
              let image = await Self.loadImage(from: localURL) else {
            return nil
        }

        imageCache.setObject(CachedPlatformImage(image: image), forKey: storageId as NSString)
        return image
    }

    func fileURL(for storageId: String?, downloadIfNeeded: Bool = false) async -> URL? {
        guard let storageId else { return nil }

        if let localURL = cachedLocalFileURL(for: storageId) {
            return localURL
        }

        if downloadIfNeeded {
            return await downloadFile(storageId: storageId)
        }

        return await resolveRemoteURL(for: storageId)
    }

    func replaceCachedFile(storageId: String, with localURL: URL) {
        guard fileManager.fileExists(atPath: localURL.path) else { return }

        let destinationURL = cacheDirectory.appendingPathComponent(cacheFileName(for: storageId, sourceURL: localURL))

        do {
            if destinationURL.standardizedFileURL != localURL.standardizedFileURL {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try? fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: localURL, to: destinationURL)
            }
            manifest[storageId] = destinationURL.lastPathComponent
            persistManifest()
            imageCache.removeObject(forKey: storageId as NSString)
        } catch {
            print("⚠️ ConvexFileCacheService: could not cache file for \(storageId): \(error)")
        }
    }

    private func resolveRemoteURL(for storageId: String) async -> URL? {
        if let entry = signedURLCache[storageId], entry.expiresAt > Date() {
            return entry.url
        }

        if let existingTask = urlTasks[storageId] {
            return await existingTask.value
        }

        let task = Task<URL?, Never> {
            guard let urlString = try? await ConvexChatAPI.shared.getFileURL(storageId: storageId),
                  let url = URL(string: urlString) else {
                return nil
            }
            return url
        }

        urlTasks[storageId] = task
        let url = await task.value
        urlTasks[storageId] = nil

        if let url {
            signedURLCache[storageId] = URLCacheEntry(
                url: url,
                expiresAt: Date().addingTimeInterval(signedURLTTL)
            )
        }

        return url
    }

    private func downloadFile(storageId: String) async -> URL? {
        if let localURL = cachedLocalFileURL(for: storageId) {
            return localURL
        }

        if let existingTask = downloadTasks[storageId] {
            return await existingTask.value
        }

        let remoteURL = await resolveRemoteURL(for: storageId)
        let task = Task<URL?, Never> {
            guard let remoteURL else { return nil }

            do {
                let (data, response) = try await URLSession.shared.data(from: remoteURL)
                let destinationURL = await MainActor.run {
                    self.cacheDirectory.appendingPathComponent(
                        self.cacheFileName(for: storageId, sourceURL: remoteURL, response: response)
                    )
                }

                try data.write(to: destinationURL, options: .atomic)

                await MainActor.run {
                    self.manifest[storageId] = destinationURL.lastPathComponent
                    self.persistManifest()
                }

                return destinationURL
            } catch {
                return nil
            }
        }

        downloadTasks[storageId] = task
        let localURL = await task.value
        downloadTasks[storageId] = nil
        return localURL
    }

    private func cacheFileName(for storageId: String, sourceURL: URL, response: URLResponse? = nil) -> String {
        let hash = SHA256.hash(data: Data(storageId.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        let pathExtension = preferredPathExtension(sourceURL: sourceURL, response: response)
        return pathExtension.isEmpty ? hash : "\(hash).\(pathExtension)"
    }

    private func preferredPathExtension(sourceURL: URL, response: URLResponse?) -> String {
        if !sourceURL.pathExtension.isEmpty {
            return sourceURL.pathExtension.lowercased()
        }

        if let mimeType = response?.mimeType {
            switch mimeType.lowercased() {
            case "image/jpeg": return "jpg"
            case "image/png": return "png"
            case "image/gif": return "gif"
            case "image/webp": return "webp"
            case "video/mp4": return "mp4"
            case "audio/m4a", "audio/mp4": return "m4a"
            case "audio/mpeg": return "mp3"
            case "audio/wav", "audio/x-wav": return "wav"
            default: break
            }
        }

        return "bin"
    }

    private func persistManifest() {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private static func loadImage(from url: URL) async -> PlatformImage? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return PlatformImage.fromData(data)
        }.value
    }
}
