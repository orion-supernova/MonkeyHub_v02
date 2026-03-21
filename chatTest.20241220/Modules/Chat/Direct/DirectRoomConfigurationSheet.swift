import SwiftUI

struct DirectRoomConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let user: ChatUser
    let actionTitle: String
    let submit: (RoomType, TimeInterval?) async -> Void

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedType: RoomType = .regular
    @State private var messageLifetime: TimeInterval = 30
    @State private var isSubmitting = false

    private let lifetimeOptions: [(String, TimeInterval)] = [
        ("10 seconds", 10),
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300),
        ("10 minutes", 600),
        ("30 minutes", 1800),
        ("1 hour", 3600),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerCard
                    roomTypeSection

                    if selectedType == .secret {
                        lifetimeSection
                    }
                }
                .padding(20)
            }
            .background(selectedTheme.colors(for: colorScheme).background)
            .navigationTitle("Start with \(user.displayName)")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSubmitting = true
                            await submit(selectedType, selectedType == .secret ? messageLifetime : nil)
                            isSubmitting = false
                            dismiss()
                        }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(actionTitle)
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: selectedTheme.colors(for: colorScheme).primary,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay {
                    Text(user.displayInitial)
                        .font(.title2.bold())
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                Text("Choose the conversation type before you continue.")
                    .font(.footnote)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }

            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(selectedTheme.colors(for: colorScheme).cardBackground)
        )
    }

    private var roomTypeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Conversation Type")
                .font(.headline)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

            ForEach([RoomType.regular, .secret], id: \.self) { type in
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        selectedType = type
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: type == .regular ? "bubble.left.and.bubble.right.fill" : "flame.fill")
                            .font(.title3)
                            .foregroundStyle(type == .regular ? Color.blue : Color.orange)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(type.rawValue)
                                .font(.headline)
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                            Text(type == .regular ? "Normal private chat." : "Messages auto-delete after a timer.")
                                .font(.footnote)
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                        }

                        Spacer()

                        Image(systemName: selectedType == type ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedType == type ? selectedTheme.colors(for: colorScheme).accent : selectedTheme.colors(for: colorScheme).textSecondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                selectedType == type
                                    ? selectedTheme.colors(for: colorScheme).accent
                                    : selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.14),
                                lineWidth: selectedType == type ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var lifetimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Message Lifetime")
                .font(.headline)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

            ForEach(lifetimeOptions, id: \.1) { option in
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        messageLifetime = option.1
                    }
                } label: {
                    HStack {
                        Text(option.0)
                            .font(.subheadline)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                        Spacer()
                        if messageLifetime == option.1 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                messageLifetime == option.1
                                    ? Color.orange.opacity(0.7)
                                    : selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.14),
                                lineWidth: messageLifetime == option.1 ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
