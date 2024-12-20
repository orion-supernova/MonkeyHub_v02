import SwiftUI

struct AlertAction {
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    static func cancel() -> AlertAction {
        AlertAction(title: "Cancel", role: .cancel, action: {})
    }
}

@MainActor
class AlertManager: ObservableObject {
    static let shared = AlertManager()

    @Published private(set) var isPresented = false
    @Published private(set) var title = ""
    @Published private(set) var message = ""
    @Published private(set) var actions: [AlertAction] = []

    private var alertQueue: [(String, String, [AlertAction])] = []

    private init() {}

    func showAlert(
        title: String,
        message: String,
        actions: [AlertAction] = []
    ) {
        if isPresented {
            // Queue this alert
            alertQueue.append((title, message, actions))
            return
        }

        self.title = title
        self.message = message
        self.actions = actions.isEmpty ? [.cancel()] : actions
        self.isPresented = true
    }

    func alertDismissed() {
        isPresented = false

        // Show next alert if queued
        if let next = alertQueue.first {
            alertQueue.removeFirst()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showAlert(
                    title: next.0,
                    message: next.1,
                    actions: next.2
                )
            }
        }
    }
}

struct AlertModifier: ViewModifier {
    @StateObject private var alertManager = AlertManager.shared

    func body(content: Content) -> some View {
        content
            .alert(
                alertManager.title,
                isPresented: .init(
                    get: { alertManager.isPresented },
                    set: { if !$0 { alertManager.alertDismissed() } }
                ),
                actions: {
                    ForEach(0..<alertManager.actions.count, id: \.self) { index in
                        let action = alertManager.actions[index]
                        Button(role: action.role) {
                            action.action()
                            alertManager.alertDismissed()
                        } label: {
                            Text(action.title)
                        }
                    }
                },
                message: {
                    Text(alertManager.message)
                }
            )
    }
}

extension View {
    func withAlertManager() -> some View {
        modifier(AlertModifier())
    }
}
