import SwiftUI

enum AuthError: LocalizedError {
    case credentialError
    case userCreationFailed
    case userNotFound
    case signInFailed
    case signOutFailed
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .credentialError:       return "Invalid credentials received"
        case .userCreationFailed:    return "Failed to create new user"
        case .userNotFound:          return "User not found"
        case .signInFailed:          return "Failed to sign in"
        case .signOutFailed:         return "Failed to sign out"
        case .unknown(let error):    return error.localizedDescription
        }
    }
}

@MainActor
class LoginViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let auth = ConvexAuthService.shared

    func signIn(username: String, password: String) {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter username and password"
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await auth.signIn(username: username, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func signUp(username: String, password: String, name: String, email: String) {
        guard !username.isEmpty, !password.isEmpty, !name.isEmpty else {
            errorMessage = "Please fill in all required fields"
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await auth.signUp(username: username, password: password, name: name, email: email)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func signOut() {
        auth.signOut()
    }
}
