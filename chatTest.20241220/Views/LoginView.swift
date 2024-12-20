import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var cloudKit: CloudKitManager
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            Text("Welcome to Chat")
                .font(.largeTitle)
                .bold()

            Text("Sign in with your Apple ID to start chatting")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            SignInWithAppleButton { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task {
                    do {
                        switch result {
                        case .success(let authorization):
                            if let appleIDCredential = authorization.credential
                                as? ASAuthorizationAppleIDCredential
                            {
                                try await cloudKit.signIn(with: appleIDCredential)
                            }
                        case .failure(let error):
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .padding()
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
}
