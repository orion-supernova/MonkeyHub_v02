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

                    // IMPORTANT: Always check if user exists FIRST
                    let userExists = try await isUserExists()

                    if userExists {
                        Logger.info("User exists, logging in...", category: .auth)
                        try await loginUser(with: credential)
                    } else {
                        Logger.info("User does not exist, creating new user...", category: .auth)
                        let email = credential.email
                        let fullName = credential.fullName
                        let username = "\(fullName?.givenName ?? "") \(fullName?.familyName ?? "")"
                            .trimmingCharacters(in: .whitespaces)

                        try await createUser(
                            with: credential,
                            name: username.isEmpty ? "I'm your name and surname" : username,
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
            Logger.info("Creating new user: \(name) (\(email))", category: .auth)
            let iCloudId = try await cloudKit.container.userRecordID()
            let userId = iCloudId.recordName
            Logger.info("Fetched iCloud ID: \(userId)", category: .auth)

            // Create user with original iCloud ID (including underscore if present)
            // The underscore will be stripped only for CKRecord.ID in toRecord()
            let newUser = ChatUser(
                id: userId,
                name: name,
                email: email
            )

            do {
                try await cloudKit.database.save(newUser.toRecord())
                Logger.info("CloudKit save successful for user \(userId)", category: .cloudKit)
            } catch let error {
                Logger.error("CloudKit Save Error: \(error.localizedDescription)", category: .cloudKit)

                // Handle the case where user already exists (e.g., environment switch)
                if let ckError = error as? CKError {
                    Logger.error("CKError Code: \(ckError.code.rawValue)", category: .cloudKit)

                    // If record already exists, try to login instead
                    if ckError.code == .serverRecordChanged || ckError.code == .batchRequestFailed {
                        Logger.info("User might already exist in different environment, attempting login...", category: .auth)
                        try await loginUser(with: credential)
                        return
                    }
                }
                throw CloudKitError.custom(error.localizedDescription)
            }

            cloudKit.isAuthenticated = true
            userDefaults.set(userId, forKey: userIdUserDefaultsKey)

            // Setup notifications for new user
            await cloudKit.syncDeviceTokenWithCloudKit()
            await cloudKit.subscribeToAllJoinedRooms()

            Logger.info("User created successfully", category: .auth)
        } catch let error {
            Logger.error("CRITICAL: Failed to create user: \(error)", category: .auth)
            throw AuthError.userCreationFailed
        }
    }

    private func loginUser(with credential: ASAuthorizationAppleIDCredential) async throws {
        do {
            let iCloudId = try await cloudKit.container.userRecordID()
            let userId = iCloudId.recordName

            userDefaults.set(userId, forKey: userIdUserDefaultsKey)
            cloudKit.isAuthenticated = true

            // Setup notifications for existing user
            await cloudKit.syncDeviceTokenWithCloudKit()
            await cloudKit.subscribeToAllJoinedRooms()

            Logger.info("User logged in successfully: \(userId)", category: .auth)
        } catch {
            Logger.error("Failed to login user: \(error)", category: .auth)
            throw AuthError.signInFailed
        }
    }

    private func isUserExists() async throws -> Bool {
        // Get the iCloud user record ID
        let iCloudId = try await cloudKit.container.userRecordID()
        let userId = iCloudId.recordName
        Logger.info("Checking if user exists with ID: \(userId)", category: .auth)

        // Check for user with iCloud ID (keep underscore as stored in field)
        let predicate = NSPredicate(format: "id == %@", userId)
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
