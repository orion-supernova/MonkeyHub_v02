import SwiftUI

struct FriendRequestPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let request: FriendRequest
    let approve: () async -> Void
    let reject: () async -> Void

    @ObservedObject private var repository = ChatRepository.shared

    @State private var isLoading = true
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if isLoading && repository.activeRequestMessages.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if repository.activeRequestMessages.isEmpty {
                        Text("No message history yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(repository.activeRequestMessages) { message in
                                messageBubble(message)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Preview Request")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                repository.setActiveRequest(request.id)
                isLoading = false
            }
            .onDisappear {
                repository.setActiveRequest(nil)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isProcessing = true
                            await approve()
                            isProcessing = false
                            dismiss()
                        }
                    } label: {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Text("Approve")
                        }
                    }
                    .disabled(isProcessing)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Reject") {
                        Task {
                            isProcessing = true
                            await reject()
                            isProcessing = false
                            dismiss()
                        }
                    }
                    .tint(.red)
                    .disabled(isProcessing)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay {
                    Text(request.user.displayInitial)
                        .font(.title2.bold())
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(request.user.displayName)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                Text(request.roomType.rawValue)
                    .font(.footnote)
                    .foregroundStyle(request.roomType == .secret ? .orange : selectedTheme.colors(for: colorScheme).accent)
                if let lifetime = request.messageLifetime {
                    Text("Messages expire after \(formatLifetime(lifetime))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private func messageBubble(_ message: FriendRequestMessage) -> some View {
        let isSender = message.userId == UserDefaults.standard.string(forKey: userIdUserDefaultsKey)
        return HStack {
            if isSender { Spacer(minLength: 60) }
            Text(message.content)
                .font(.body)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            isSender
                                ? AnyShapeStyle(LinearGradient(
                                    colors: selectedTheme.colors(for: colorScheme).primary,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                  ))
                                : AnyShapeStyle(selectedTheme.colors(for: colorScheme).cardBackground)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            isSender
                                ? Color.clear
                                : selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.2),
                            lineWidth: 1
                        )
                )
            if !isSender { Spacer(minLength: 60) }
        }
    }

    private func formatLifetime(_ lifetime: TimeInterval) -> String {
        let seconds = Int(lifetime)
        if seconds >= 3600 {
            return "\(seconds / 3600) hour" + (seconds >= 7200 ? "s" : "")
        }
        if seconds >= 60 {
            return "\(seconds / 60) minute" + (seconds >= 120 ? "s" : "")
        }
        return "\(seconds) second" + (seconds == 1 ? "" : "s")
    }
}
