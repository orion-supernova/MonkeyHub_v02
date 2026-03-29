import Foundation
import CryptoKit

struct SecurityUtils {
    /// Hashes a string using SHA256 and returns its hex representation.
    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
