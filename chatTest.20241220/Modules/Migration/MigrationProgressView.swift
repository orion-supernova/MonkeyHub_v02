import SwiftUI

/// View that displays migration progress to the user
///
/// This view shows:
/// - A modal overlay that prevents interaction
/// - Progress indicator with percentage
/// - Current migration step description
/// - Error messages with retry option if migration fails
struct MigrationProgressView: View {
    @ObservedObject var migrationRunner: MigrationRunner
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            // Progress card
            VStack(spacing: 24) {
                // Header
                Text("Updating App Data")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Progress indicator
                progressView

                // Status message
                Text(migrationRunner.state.userMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                // Action button (if failed)
                if case .failed = migrationRunner.state {
                    retryButton
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.systemGray6 : Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
    }

    @ViewBuilder
    private var progressView: some View {
        switch migrationRunner.state {
        case .notStarted, .inProgress:
            VStack(spacing: 16) {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(
                            Color.gray.opacity(0.2),
                            lineWidth: 8
                        )
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: migrationRunner.progress)
                        .stroke(
                            Color.blue,
                            style: StrokeStyle(
                                lineWidth: 8,
                                lineCap: .round
                            )
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: migrationRunner.progress)

                    Text("\(Int(migrationRunner.progress * 100))%")
                        .font(.headline)
                        .foregroundColor(.blue)
                }

                // Step indicator
                if case .inProgress(let current, let total, _) = migrationRunner.state {
                    Text("Step \(current) of \(total)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case .completed:
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("Complete!")
                    .font(.caption)
                    .foregroundColor(.green)
            }

        case .failed:
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 80, height: 80)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                }

                Text("Failed")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var retryButton: some View {
        Button(action: {
            Task {
                try? await migrationRunner.migrate(to: 2)  // Retry migration
            }
        }) {
            Text("Retry")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
        }
        .padding(.horizontal)
    }
}

/// Preview for SwiftUI canvas
struct MigrationProgressView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // In progress
            MigrationProgressView(
                migrationRunner: {
                    let runner = MigrationRunner(
                        database: CloudKitManager.shared.database
                    )
                    runner.state = .inProgress(current: 1, total: 3, description: "Adding user profiles")
                    runner.progress = 0.33
                    return runner
                }()
            )
            .previewDisplayName("In Progress")

            // Completed
            MigrationProgressView(
                migrationRunner: {
                    let runner = MigrationRunner(
                        database: CloudKitManager.shared.database
                    )
                    runner.state = .completed
                    runner.progress = 1.0
                    return runner
                }()
            )
            .previewDisplayName("Completed")

            // Failed
            MigrationProgressView(
                migrationRunner: {
                    let runner = MigrationRunner(
                        database: CloudKitManager.shared.database
                    )
                    runner.state = .failed(
                        error: MigrationError.migrationFailed(
                            version: 2,
                            reason: "Network connection lost"
                        )
                    )
                    return runner
                }()
            )
            .previewDisplayName("Failed")
        }
    }
}
