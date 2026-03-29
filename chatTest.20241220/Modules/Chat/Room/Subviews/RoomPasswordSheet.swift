import SwiftUI

struct RoomPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    let roomName: String
    let submit: (String) async -> String?

    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(roomName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Protected")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(selectedTheme.colors(for: colorScheme).accent.opacity(0.12))
                    .clipShape(Capsule())
                }

                Text("This room requires a password before you can join.")
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)

                SecureField("Room password", text: $password)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(selectedTheme.colors(for: colorScheme).cardBackground)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.14), lineWidth: 1)
                    )
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        isSubmitting = true
                        errorMessage = await submit(password)
                        isSubmitting = false
                        if errorMessage == nil {
                            dismiss()
                        }
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Join Room")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(selectedTheme.colors(for: colorScheme).accent)
                )
                .disabled(isSubmitting || password.isEmpty)
                .opacity(isSubmitting || password.isEmpty ? 0.6 : 1)

                Spacer()
            }
            .padding()
            .background(selectedTheme.colors(for: colorScheme).background)
            .navigationTitle("Enter Password")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 220, idealHeight: 240)
        #endif
    }
}
