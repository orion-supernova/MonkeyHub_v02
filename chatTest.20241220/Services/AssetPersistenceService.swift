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
