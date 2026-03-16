import Combine
import ConvexMobile
import Foundation

/// Singleton wrapper around the ConvexMobile client.
/// All Convex network operations go through here.
final class ConvexService {
    static let shared = ConvexService()

    let client: ConvexClient

    /// One-shot query: subscribes, takes first value, cancels.
    /// ConvexMobile only exposes reactive subscriptions for queries — this bridges to async/await.
    func queryOnce<T: Decodable>(_ name: String, with args: [String: ConvexEncodable?]? = nil) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            var hasResumed = false

            cancellable = client
                .subscribe(to: name, with: args, yielding: T.self)
                .first()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let err) = completion, !hasResumed {
                            hasResumed = true
                            continuation.resume(throwing: err)
                        }
                        cancellable = nil
                    },
                    receiveValue: { value in
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(returning: value)
                        }
                        cancellable = nil
                    }
                )
        }
    }

    private static var deploymentURL: String {
        Bundle.main.object(forInfoDictionaryKey: "CONVEX_URL") as? String
            ?? ProcessInfo.processInfo.environment["CONVEX_URL"]
            ?? "https://termio-api.walhallaa.com"
    }

    private init() {
        client = ConvexClient(deploymentUrl: Self.deploymentURL)
    }
}

/// Errors surfaced by Convex operations.
enum ConvexError: LocalizedError {
    case notAuthenticated
    case serverError(String)
    case decodingError(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be logged in to perform this action"
        case .serverError(let msg): return msg
        case .decodingError(let msg): return "Data error: \(msg)"
        case .unknown(let err): return err.localizedDescription
        }
    }
}
