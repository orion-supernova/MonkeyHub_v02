import AuthenticationServices
import CloudKit
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
        case .credentialError:
            return "Invalid credentials received"
        case .userCreationFailed:
            return "Failed to create new user"
        case .userNotFound:
            return "User not found"
        case .signInFailed:
            return "Failed to sign in"
        case .signOutFailed:
            return "Failed to sign out"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

@MainActor
class LoginViewModel: ObservableObject {
    private let cloudKit: CloudKitManager

    init(cloudKit: CloudKitManager = .shared) {
        self.cloudKit = cloudKit
    }

    func handleSignInWithApple(_ result: Result<ASAuthorization, Error>) {
        Task {
            do {
                switch result {
                case .success(let authorization):
                    guard
                        let credential = authorization.credential
                            as? ASAuthorizationAppleIDCredential
                    else {
                        throw AuthError.credentialError
                    }

                    let userExists = try await isUserExists()

                    if userExists {
                        try await loginUser(with: credential)
                    } else {

                        let email = credential.email
                        let fullName = credential.fullName
                        let userName = "\(fullName?.givenName ?? "") \(fullName?.familyName ?? "")"
                            .trimmingCharacters(in: .whitespaces)

                        try await createUser(
                            with: credential,
                            name: userName.isEmpty ? "I'm just a username" : userName,
                            email: email ?? "I'm your email address"
                        )
                    }

                case .failure(let error):
                    throw AuthError.unknown(error)
                }
            } catch let error {
                handleError(error)
            }
        }
    }

    private func createUser(
        with credential: ASAuthorizationAppleIDCredential,
        name: String,
        email: String
    ) async throws {
        do {
            let iCloudId = try await cloudKit.container.userRecordID()

            let newRecord = CKRecord(recordType: "ChatUser")
            newRecord["id"] = iCloudId.recordName  // Use iCloud ID instead of UUID
            newRecord["name"] = name
            newRecord["email"] = email
            
            do {
                try await cloudKit.database.save(newRecord)
            } catch let error {
                Logger.error(error.localizedDescription, category: .cloudKit)
                throw CloudKitError.custom(error.localizedDescription)
            }

            cloudKit.isAuthenticated = true
            userDefaults.set(iCloudId.recordName, forKey: userIdUserDefaultsKey)
            
            Logger.info("User created successfully", category: .auth)
        } catch let error {
            Logger.error("Failed to create user: \(error)", category: .auth)
            throw AuthError.userCreationFailed
        }
    }

    private func loginUser(with credential: ASAuthorizationAppleIDCredential) async throws {
        do {
            let iCloudId = try await cloudKit.container.userRecordID()
            let id = iCloudId.recordName
            
            userDefaults.set(id, forKey: userIdUserDefaultsKey)
            cloudKit.isAuthenticated = true
            Logger.info("User logged in successfully: \(id)", category: .auth)
        } catch {
            Logger.error("Failed to login user: \(error)", category: .auth)
            throw AuthError.signInFailed
        }
    }

    private func isUserExists() async throws -> Bool {
        // Get the iCloud user record ID
        let iCloudId = try await cloudKit.container.userRecordID()

        // Check for user with iCloud ID
        let predicate = NSPredicate(format: "id == %@", iCloudId.recordName)
        let query = CKQuery(recordType: "ChatUser", predicate: predicate)

        do {
            let (records, _) = try await cloudKit.database.records(matching: query)
            return try records.first?.1.get() != nil
        } catch let error as CKError where error.code == .unknownItem {
            // This error means the record type doesn't exist yet (first app launch)
            Logger.info("No ChatUser records exist yet", category: .auth)
            return false
        } catch let error as CKError where error.code == .zoneNotFound {
            // This error can occur when the zone is being created
            Logger.info("CloudKit zone not found, likely first launch", category: .auth)
            return false
        } catch let error {
            // Log and rethrow other errors that might indicate actual problems
            Logger.error("Failed to check user existence: \(error)", category: .auth)
            throw AuthError.unknown(error)
        }
    }

    func signOut() {
        cloudKit.signOut()
    }

    private func handleError(_ error: Error) {
        let authError = (error as? AuthError) ?? AuthError.unknown(error)
        AlertManager.shared.showAlert(
            title: "Error",
            message: authError.localizedDescription
        )
    }
}
