import AuthenticationServices
import CloudKit
import SwiftUI

@MainActor
class LoginViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var showError = false
    @Published var errorMessage = ""
    private let cloudKit = CloudKitManager.shared

    func handleSignInWithAppleResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential
            {
                do {
                    // Get user info from Apple ID credential
                    let userId = appleIDCredential.user
                    let email = appleIDCredential.email ?? ""
                    let fullName = appleIDCredential.fullName
                    let givenName = fullName?.givenName ?? "User"

                    // Create or update user in CloudKit
                    let newRecord = CKRecord(recordType: "ChatUser")
                    newRecord["id"] = userId
                    newRecord["name"] = givenName
                    newRecord["email"] = email

                    let saveResult = try await cloudKit.database.modifyRecords(
                        saving: [newRecord], deleting: []
                    ).saveResults.first?.1.get()

                    guard saveResult != nil else {
                        throw CloudKitError.operationFailed
                    }

                    // Set the current user
                    let user = try ChatUser(from: saveResult!)
                    cloudKit.currentUser = user

                    isAuthenticated = true
                } catch {
                    errorMessage = "Failed to save user data: \(error.localizedDescription)"
                    showError = true
                }
            }
        case .failure(let error):
            errorMessage = "Sign in failed: \(error.localizedDescription)"
            showError = true
        }
    }
}
