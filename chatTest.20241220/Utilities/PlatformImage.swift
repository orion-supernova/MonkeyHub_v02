import SwiftUI

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    /// Convert PlatformImage to Data for Convex file storage
    func toData() -> Data? {
        #if canImport(UIKit)
        return self.jpegData(compressionQuality: 0.8)
        #elseif canImport(AppKit)
        guard let tiffRepresentation = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        #endif
    }
    
    /// Create PlatformImage from Data
    static func fromData(_ data: Data) -> PlatformImage? {
        return PlatformImage(data: data)
    }

    /// Create PlatformImage from file path
    static func fromFile(_ path: String) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(contentsOfFile: path)
        #elseif canImport(AppKit)
        return NSImage(contentsOfFile: path)
        #endif
    }
}

/// A platform-agnostic SwiftUI Image initializer
extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}
