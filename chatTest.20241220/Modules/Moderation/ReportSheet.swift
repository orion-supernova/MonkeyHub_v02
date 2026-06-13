import SwiftUI

/// Reusable moderation report form for a user, message, or room.
struct ReportSheet: View {
    enum Target {
        case user(id: String, name: String)
        case message(id: String)
        case room(id: String, name: String)

        var type: String {
            switch self {
            case .user: return "user"
            case .message: return "message"
            case .room: return "room"
            }
        }
        var id: String {
            switch self {
            case .user(let id, _), .message(let id), .room(let id, _): return id
            }
        }
        var subtitle: String {
            switch self {
            case .user(_, let name): return "Reporting \(name)"
            case .message: return "Reporting a message"
            case .room(_, let name): return "Reporting \(name)"
            }
        }
    }

    let target: Target

    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ReportSheet.reasons.first ?? "Spam"
    @State private var note = ""
    @State private var isSubmitting = false

    static let reasons = ["Spam", "Harassment or bullying", "Inappropriate content", "Impersonation", "Other"]

    private var theme: ThemeColors { selectedTheme.colors(for: colorScheme) }
    private var userId: String { userDefaults.string(forKey: userIdUserDefaultsKey) ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(target.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("REASON")
                            .font(.caption.bold())
                            .foregroundStyle(theme.textSecondary)
                        ForEach(Self.reasons, id: \.self) { r in
                            Button {
                                reason = r
                            } label: {
                                HStack {
                                    Text(r)
                                        .foregroundStyle(theme.textPrimary)
                                    Spacer()
                                    if reason == r {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(theme.accent)
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12).fill(theme.cardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ADDITIONAL DETAILS (OPTIONAL)")
                            .font(.caption.bold())
                            .foregroundStyle(theme.textSecondary)
                        TextField("Add a note…", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12).fill(theme.cardBackground)
                            )
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(theme.text) }
                            Text(isSubmitting ? "Submitting…" : "Submit Report")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(theme.text)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(LinearGradient(colors: theme.primary, startPoint: .leading, endPoint: .trailing))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }
                .padding(20)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Report")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        guard !userId.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await ConvexChatAPI.shared.report(
                reporterId: userId,
                targetType: target.type,
                targetId: target.id,
                reason: reason,
                note: note
            )
            dismiss()
            AlertManager.shared.showAlert(title: "Report Submitted", message: "Thanks — our team will review this.")
        } catch {
            AlertManager.shared.showAlert(title: "Error", message: "Could not submit report: \(error.localizedDescription)")
        }
    }
}
