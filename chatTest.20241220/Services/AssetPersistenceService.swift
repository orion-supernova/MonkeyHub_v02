import Foundation
import CloudKit

/// Responsible for moving CloudKit assets from temporary to permanent local storage.
class AssetPersistenceService {
    static let shared = AssetPersistenceService()
    
    private let fileManager = FileManager.default
    
    private var assetsDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let assetsDir = documentsDirectory.appendingPathComponent("ChatAssets", isDirectory: true)
        
        if !fileManager.fileExists(atPath: assetsDir.path) {
            try? fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        }
        return assetsDir
    }
    
    private init() {}
    
    /// Persists a CloudKit asset to a permanent local location.
    /// - Parameter asset: The CKAsset from CloudKit
    /// - Returns: The new permanent local URL, or the original if persistence fails
    func persistAsset(_ asset: CKAsset) -> URL? {
        guard let sourceURL = asset.fileURL else { return nil }
        
        // Use a hash or UUID for the filename to avoid collisions and keep it stable
        let fileName = sourceURL.lastPathComponent
        let destinationURL = assetsDirectory.appendingPathComponent(fileName)
        
        // If already exists, just return it
        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            print("💾 AssetPersistenceService: Persisted asset to \(destinationURL.lastPathComponent)")
            return destinationURL
        } catch {
            print("❌ AssetPersistenceService: Failed to persist asset: \(error.localizedDescription)")
            return sourceURL // Fallback to temporary URL
        }
    }
}
